# 实现示例：TypeScript + Node.js

本示例给出一个完整的 VCDDD `PlaceOrder` 实现，技术栈为 TypeScript + Express + Prisma + PostgreSQL + pino。

目标约束：
- 订单核心对象集中在 `server/order/`；除 `prisma.repository.ts` 外，其余文件不引入 Express、Prisma、pino 等框架包
- `app/` 只做协议适配：解析参数 -> 调用 `server` -> 序列化响应
- `server/order/prisma.repository.ts` 负责 Prisma 持久化与事务边界
- 幂等键由调用方提供，并在 Prisma 事务内用唯一索引原子检测
- 一个聚合一笔事务，事务提交后再发布 `OrderPlaced`
- `OrderError` 表示业务拒绝，不应重试；未捕获异常视为系统异常，可重试

## 项目目录

```text
src/
├── app/
│   ├── main.ts                            # Express 入口，组装 Prisma、pino、路由、错误处理中间件
│   ├── middleware/
│   │   └── trace.middleware.ts           # 生成或透传 trace_id，并回写响应头
│   └── routes/
│       └── order.routes.ts               # HTTP -> PlaceOrderCommand 的适配层
├── server/
│   └── order/
│       ├── aggregate.ts                  # 订单聚合、不变量、OrderError
│       ├── commands.ts                   # PlaceOrder 命令处理流程
│       ├── events.ts                     # OrderPlaced 事件定义与构造
│       ├── repository.ts                 # 事务端口与仓储接口
│       ├── prisma.repository.ts          # OrderRepository 的 Prisma/PostgreSQL 实现
│       └── read_model.ts                 # 命令所需读模型
└── prisma/
    └── schema.prisma                     # PostgreSQL 模型，含幂等唯一索引
```

## Prisma Schema（支撑文件）

`saveWithIdempotencyCheck` 依赖唯一索引，因此这里补上最小可运行 schema：

```prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id        String   @id @db.Uuid
  isBanned  Boolean  @default(false)
  orders    Order[]
}

model Inventory {
  sku               String   @id
  availableQuantity Int
  unitPriceCents    Int
  updatedAt         DateTime @updatedAt
}

model Order {
  id               String            @id @db.Uuid
  userId           String            @db.Uuid
  status           String
  totalAmountCents Int
  createdAt        DateTime
  user             User              @relation(fields: [userId], references: [id])
  items            OrderItem[]
  idempotency      OrderIdempotency?

  @@index([userId, createdAt])
}

model OrderItem {
  id             String @id @default(cuid())
  orderId        String @db.Uuid
  sku            String
  quantity       Int
  unitPriceCents Int
  lineTotalCents Int
  order          Order  @relation(fields: [orderId], references: [id], onDelete: Cascade)

  @@index([orderId])
}

model OrderIdempotency {
  key       String   @id
  orderId   String   @unique @db.Uuid
  createdAt DateTime @default(now())
  order     Order    @relation(fields: [orderId], references: [id], onDelete: Cascade)
}
```

## server/order/aggregate.ts

```typescript
import type { OrderPlacedEvent } from './events';
import type { InventoryReadModel } from './read_model';

export type OrderStatus = 'PENDING';

export type OrderErrorCode =
  | 'EMPTY_ORDER'
  | 'INVALID_ITEM_QUANTITY'
  | 'INVALID_TOTAL'
  | 'MISSING_IDEMPOTENCY_KEY'
  | 'USER_NOT_FOUND'
  | 'USER_BANNED'
  | 'INSUFFICIENT_INVENTORY'
  | 'DUPLICATE_IDEMPOTENCY_KEY';

export class OrderError extends Error {
  readonly name = 'OrderError';
  readonly retryable = false;

  constructor(
    public readonly code: OrderErrorCode,
    message: string,
    public readonly details: Record<string, unknown> = {},
  ) {
    super(message);
  }
}

export interface PlaceOrderItemInput {
  sku: string;
  quantity: number;
}

export interface OrderLine {
  sku: string;
  quantity: number;
  unitPriceCents: number;
  lineTotalCents: number;
}

export interface PlaceOrderProps {
  traceId: string;
  orderId: string;
  userId: string;
  items: readonly PlaceOrderItemInput[];
  inventory: readonly InventoryReadModel[];
  createdAt: Date;
}

export class OrderAggregate {
  private constructor(
    public readonly id: string,
    public readonly userId: string,
    public readonly status: OrderStatus,
    public readonly totalAmountCents: number,
    public readonly items: readonly OrderLine[],
    public readonly createdAt: Date,
  ) {}

  static place(
    props: PlaceOrderProps,
  ): { order: OrderAggregate; event: OrderPlacedEvent } {
    if (props.items.length === 0) {
      throw new OrderError('EMPTY_ORDER', '订单至少包含一件商品');
    }

    const inventoryBySku = new Map(
      props.inventory.map((item) => [item.sku, item]),
    );

    const lines = props.items.map((item) => {
      if (!Number.isInteger(item.quantity) || item.quantity <= 0) {
        throw new OrderError(
          'INVALID_ITEM_QUANTITY',
          `商品 ${item.sku} 的数量必须为正整数`,
          { sku: item.sku, quantity: item.quantity },
        );
      }

      const stock = inventoryBySku.get(item.sku);
      if (!stock || stock.availableQuantity < item.quantity) {
        throw new OrderError(
          'INSUFFICIENT_INVENTORY',
          `商品 ${item.sku} 库存不足`,
          {
            sku: item.sku,
            requestedQuantity: item.quantity,
            availableQuantity: stock?.availableQuantity ?? 0,
          },
        );
      }

      const lineTotalCents = stock.unitPriceCents * item.quantity;
      return {
        sku: item.sku,
        quantity: item.quantity,
        unitPriceCents: stock.unitPriceCents,
        lineTotalCents,
      };
    });

    const totalAmountCents = lines.reduce(
      (sum, item) => sum + item.lineTotalCents,
      0,
    );

    if (totalAmountCents <= 0) {
      throw new OrderError(
        'INVALID_TOTAL',
        '订单总金额必须大于 0',
        { totalAmountCents },
      );
    }

    const order = new OrderAggregate(
      props.orderId,
      props.userId,
      'PENDING',
      totalAmountCents,
      lines,
      props.createdAt,
    );

    return {
      order,
      event: {
        type: 'OrderPlaced',
        traceId: props.traceId,
        orderId: order.id,
        userId: order.userId,
        status: order.status,
        totalAmountCents: order.totalAmountCents,
        occurredAt: order.createdAt.toISOString(),
        items: order.items.map((item) => ({
          sku: item.sku,
          quantity: item.quantity,
          unitPriceCents: item.unitPriceCents,
          lineTotalCents: item.lineTotalCents,
        })),
      },
    };
  }
}
```

## server/order/read_model.ts

```typescript
export interface UserReadModel {
  userId: string;
  isBanned: boolean;
}

export interface InventoryReadModel {
  sku: string;
  availableQuantity: number;
  unitPriceCents: number;
}

export interface PlacedOrderReadModel {
  orderId: string;
  userId: string;
  status: 'PENDING';
  totalAmountCents: number;
  createdAt: string;
}
```

## server/order/events.ts

```typescript
export interface OrderPlacedEvent {
  type: 'OrderPlaced';
  traceId: string;
  orderId: string;
  userId: string;
  status: 'PENDING';
  totalAmountCents: number;
  occurredAt: string;
  items: Array<{
    sku: string;
    quantity: number;
    unitPriceCents: number;
    lineTotalCents: number;
  }>;
}
```

## server/order/repository.ts

```typescript
import type { OrderAggregate, OrderLine } from './aggregate';
import type { InventoryReadModel, UserReadModel } from './read_model';

export interface OrderTransaction {
  findUser(userId: string): Promise<UserReadModel | null>;
  getInventoryBySku(skus: readonly string[]): Promise<InventoryReadModel[]>;
  reserveInventory(items: readonly OrderLine[]): Promise<void>;
  saveWithIdempotencyCheck(
    order: OrderAggregate,
    idempotencyKey: string,
  ): Promise<void>;
}

export interface OrderRepository {
  withTransaction<T>(work: (tx: OrderTransaction) => Promise<T>): Promise<T>;
  findByIdempotencyKey(
    idempotencyKey: string,
  ): Promise<import('./read_model').PlacedOrderReadModel | null>;
}
```

## server/order/commands.ts

```typescript
import { randomUUID } from 'node:crypto';

import {
  OrderAggregate,
  OrderError,
  type PlaceOrderItemInput,
} from './aggregate';
import type { OrderPlacedEvent } from './events';
import type { OrderRepository } from './repository';
import type { PlacedOrderReadModel } from './read_model';

export interface PlaceOrderCommand {
  traceId: string;
  idempotencyKey: string;
  userId: string;
  items: readonly PlaceOrderItemInput[];
}

export interface PlaceOrderResult {
  orderId: string;
  status: 'PENDING';
  totalAmountCents: number;
}

export interface OrderLogFields {
  domain: 'order';
  action: string;
  trace_id: string;
  order_id: string | null;
  user_id: string | null;
  [key: string]: unknown;
}

export interface OrderLogger {
  info(message: string, fields: OrderLogFields): void;
  warn(message: string, fields: OrderLogFields): void;
  error(message: string, fields: OrderLogFields): void;
}

export interface PlaceOrderDeps {
  repository: OrderRepository;
  publishEvent(event: OrderPlacedEvent): Promise<void>;
  log: OrderLogger;
  now?: () => Date;
  nextOrderId?: () => string;
}

export async function placeOrder(
  command: PlaceOrderCommand,
  deps: PlaceOrderDeps,
): Promise<PlaceOrderResult> {
  const now = deps.now ?? (() => new Date());
  const orderId = (deps.nextOrderId ?? randomUUID)();

  deps.log.info('place order command entry', {
    domain: 'order',
    action: 'place_order.command_entry',
    trace_id: command.traceId,
    order_id: null,
    user_id: command.userId || null,
    idempotency_key: command.idempotencyKey,
    item_count: command.items.length,
  });

  if (!command.idempotencyKey.trim()) {
    const error = new OrderError(
      'MISSING_IDEMPOTENCY_KEY',
      '缺少幂等键',
    );
    logBusinessFailure(deps.log, command, null, error);
    throw error;
  }

  let event!: OrderPlacedEvent;
  try {
    event = await deps.repository.withTransaction(async (tx) => {
      const user = await tx.findUser(command.userId);
      if (!user) {
        const error = new OrderError(
          'USER_NOT_FOUND',
          `用户 ${command.userId} 不存在`,
          { userId: command.userId },
        );
        logBusinessFailure(deps.log, command, null, error);
        throw error;
      }

      if (user.isBanned) {
        const error = new OrderError(
          'USER_BANNED',
          `用户 ${command.userId} 已被禁用`,
          { userId: command.userId },
        );
        logBusinessFailure(deps.log, command, null, error);
        throw error;
      }

      const inventory = await tx.getInventoryBySku(
        command.items.map((item) => item.sku),
      );

      let order: OrderAggregate;
      let producedEvent: OrderPlacedEvent;
      try {
        const placed = OrderAggregate.place({
          traceId: command.traceId,
          orderId,
          userId: command.userId,
          items: command.items,
          inventory,
          createdAt: now(),
        });
        order = placed.order;
        producedEvent = placed.event;
      } catch (error) {
        if (error instanceof OrderError) {
          logBusinessFailure(deps.log, command, orderId, error);
        }
        throw error;
      }

      try {
        await tx.reserveInventory(order.items);
        await tx.saveWithIdempotencyCheck(order, command.idempotencyKey);
      } catch (error) {
        if (isDuplicateIdempotencyHit(error)) {
          throw error;
        }
        if (error instanceof OrderError) {
          logBusinessFailure(deps.log, command, order.id, error);
        }
        throw error;
      }

      deps.log.info('order state transitioned', {
        domain: 'order',
        action: 'order.state_transition',
        trace_id: command.traceId,
        order_id: order.id,
        user_id: command.userId,
        from_state: 'CREATED',
        to_state: 'PENDING',
        total_amount_cents: order.totalAmountCents,
      });

      return producedEvent;
    });
  } catch (error) {
    if (isDuplicateIdempotencyHit(error)) {
      const existing = await deps.repository.findByIdempotencyKey(
        command.idempotencyKey,
      );
      if (existing) {
        return toPlaceOrderResult(existing);
      }
    }
    throw error;
  }

  await deps.publishEvent(event);

  return {
    orderId: event.orderId,
    status: event.status,
    totalAmountCents: event.totalAmountCents,
  };
}

function logBusinessFailure(
  log: OrderLogger,
  command: PlaceOrderCommand,
  orderId: string | null,
  error: OrderError,
): void {
  log.warn('place order rejected', {
    domain: 'order',
    action: 'place_order.rejected',
    trace_id: command.traceId,
    order_id: orderId,
    user_id: command.userId || null,
    error_classification: 'business_rejection',
    retryable: false,
    reason: error.code,
    message: error.message,
    ...error.details,
  });
}

function isDuplicateIdempotencyHit(error: unknown): boolean {
  return (
    error instanceof OrderError &&
    error.code === 'DUPLICATE_IDEMPOTENCY_KEY'
  );
}

function toPlaceOrderResult(
  order: PlacedOrderReadModel,
): PlaceOrderResult {
  return {
    orderId: order.orderId,
    status: order.status,
    totalAmountCents: order.totalAmountCents,
  };
}
```

## server/order/prisma.repository.ts

```typescript
import { Prisma, PrismaClient } from '@prisma/client';

import { OrderError, type OrderAggregate, type OrderLine } from './aggregate';
import type { OrderRepository, OrderTransaction } from './repository';
import type { InventoryReadModel, UserReadModel } from './read_model';

type PrismaTx = Prisma.TransactionClient;

export class PrismaOrderRepository implements OrderRepository {
  constructor(private readonly prisma: PrismaClient) {}

  async withTransaction<T>(
    work: (tx: OrderTransaction) => Promise<T>,
  ): Promise<T> {
    return this.prisma.$transaction(
      async (tx) => work(new PrismaOrderTransaction(tx)),
      {
        isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
      },
    );
  }

  async findByIdempotencyKey(
    idempotencyKey: string,
  ): Promise<import('./read_model').PlacedOrderReadModel | null> {
    const row = await this.prisma.orderIdempotency.findUnique({
      where: {
        key: idempotencyKey,
      },
      select: {
        order: {
          select: {
            id: true,
            userId: true,
            status: true,
            totalAmountCents: true,
            createdAt: true,
          },
        },
      },
    });

    if (!row?.order) {
      return null;
    }

    return {
      orderId: row.order.id,
      userId: row.order.userId,
      status: row.order.status as 'PENDING',
      totalAmountCents: row.order.totalAmountCents,
      createdAt: row.order.createdAt.toISOString(),
    };
  }
}

class PrismaOrderTransaction implements OrderTransaction {
  constructor(private readonly tx: PrismaTx) {}

  async findUser(userId: string): Promise<UserReadModel | null> {
    const user = await this.tx.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        isBanned: true,
      },
    });

    if (!user) {
      return null;
    }

    return {
      userId: user.id,
      isBanned: user.isBanned,
    };
  }

  async getInventoryBySku(
    skus: readonly string[],
  ): Promise<InventoryReadModel[]> {
    const uniqueSkus = [...new Set(skus)];
    if (uniqueSkus.length === 0) {
      return [];
    }

    const rows = await this.tx.inventory.findMany({
      where: {
        sku: {
          in: uniqueSkus,
        },
      },
      select: {
        sku: true,
        availableQuantity: true,
        unitPriceCents: true,
      },
    });

    return rows.map((row) => ({
      sku: row.sku,
      availableQuantity: row.availableQuantity,
      unitPriceCents: row.unitPriceCents,
    }));
  }

  async reserveInventory(items: readonly OrderLine[]): Promise<void> {
    for (const item of items) {
      const updated = await this.tx.inventory.updateMany({
        where: {
          sku: item.sku,
          availableQuantity: {
            gte: item.quantity,
          },
        },
        data: {
          availableQuantity: {
            decrement: item.quantity,
          },
        },
      });

      if (updated.count !== 1) {
        throw new OrderError(
          'INSUFFICIENT_INVENTORY',
          `商品 ${item.sku} 库存不足`,
          {
            sku: item.sku,
            requestedQuantity: item.quantity,
          },
        );
      }
    }
  }

  async saveWithIdempotencyCheck(
    order: OrderAggregate,
    idempotencyKey: string,
  ): Promise<void> {
    await this.tx.order.create({
      data: {
        id: order.id,
        userId: order.userId,
        status: order.status,
        totalAmountCents: order.totalAmountCents,
        createdAt: order.createdAt,
        items: {
          create: order.items.map((item) => ({
            sku: item.sku,
            quantity: item.quantity,
            unitPriceCents: item.unitPriceCents,
            lineTotalCents: item.lineTotalCents,
          })),
        },
      },
    });

    try {
      await this.tx.orderIdempotency.create({
        data: {
          key: idempotencyKey,
          orderId: order.id,
        },
      });
    } catch (error) {
      if (isUniqueConstraintError(error)) {
        throw new OrderError(
          'DUPLICATE_IDEMPOTENCY_KEY',
          `幂等键 ${idempotencyKey} 已被使用`,
          { idempotencyKey },
        );
      }
      throw error;
    }
  }
}

function isUniqueConstraintError(error: unknown): boolean {
  return (
    error instanceof Prisma.PrismaClientKnownRequestError &&
    error.code === 'P2002'
  );
}
```

## app/middleware/trace.middleware.ts

```typescript
import { randomUUID } from 'node:crypto';
import type { NextFunction, Request, Response } from 'express';

declare global {
  namespace Express {
    interface Request {
      traceId: string;
    }
  }
}

export const TRACE_HEADER = 'x-trace-id';

export function traceMiddleware(
  req: Request,
  res: Response,
  next: NextFunction,
): void {
  const incoming = req.header(TRACE_HEADER)?.trim();
  const traceId = incoming || randomUUID();

  req.traceId = traceId;
  res.setHeader(TRACE_HEADER, traceId);

  next();
}
```

## app/routes/order.routes.ts

```typescript
import { Router, type NextFunction, type Request, type Response } from 'express';

import { OrderError } from '../../server/order/aggregate';
import {
  placeOrder,
  type OrderLogger,
} from '../../server/order/commands';
import type { OrderPlacedEvent } from '../../server/order/events';
import type { OrderRepository } from '../../server/order/repository';

interface CreateOrderRouterDeps {
  repository: OrderRepository;
  publishEvent(event: OrderPlacedEvent): Promise<void>;
  log: OrderLogger;
}

interface PlaceOrderBody {
  userId?: unknown;
  idempotencyKey?: unknown;
  items?: Array<{
    sku?: unknown;
    quantity?: unknown;
  }>;
}

export function createOrderRouter(deps: CreateOrderRouterDeps): Router {
  const router = Router();

  router.post(
    '/',
    async (req: Request, res: Response, next: NextFunction) => {
      const body = (req.body ?? {}) as PlaceOrderBody;

      try {
        const result = await placeOrder(
          {
            traceId: req.traceId,
            idempotencyKey: readIdempotencyKey(req, body),
            userId: asString(body.userId),
            items: Array.isArray(body.items)
              ? body.items.map((item) => ({
                  sku: asString(item.sku),
                  quantity: Number(item.quantity),
                }))
              : [],
          },
          deps,
        );

        res.status(201).json(result);
      } catch (error) {
        if (error instanceof OrderError) {
          res.status(toHttpStatus(error)).json({
            error: error.code,
            message: error.message,
            traceId: req.traceId,
            retryable: error.retryable,
          });
          return;
        }

        next(error);
      }
    },
  );

  return router;
}

function readIdempotencyKey(
  req: Request,
  body: PlaceOrderBody,
): string {
  const headerValue =
    req.header('idempotency-key') ??
    req.header('x-idempotency-key');

  if (headerValue?.trim()) {
    return headerValue.trim();
  }

  return asString(body.idempotencyKey);
}

function asString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function toHttpStatus(error: OrderError): number {
  switch (error.code) {
    case 'USER_NOT_FOUND':
      return 404;
    case 'USER_BANNED':
      return 403;
    case 'INSUFFICIENT_INVENTORY':
      return 409;
    case 'EMPTY_ORDER':
    case 'INVALID_ITEM_QUANTITY':
    case 'INVALID_TOTAL':
    case 'MISSING_IDEMPOTENCY_KEY':
      return 422;
    default:
      return 422;
  }
}
```

## app/main.ts

```typescript
import express, { type NextFunction, type Request, type Response } from 'express';
import pino from 'pino';
import { PrismaClient } from '@prisma/client';

import { traceMiddleware } from './middleware/trace.middleware';
import { createOrderRouter } from './routes/order.routes';
import type { OrderLogger } from '../server/order/commands';
import type { OrderPlacedEvent } from '../server/order/events';
import { PrismaOrderRepository } from '../server/order/prisma.repository';

const app = express();
const prisma = new PrismaClient();

const logger = pino({
  level: process.env.LOG_LEVEL ?? 'info',
  base: undefined,
  timestamp: pino.stdTimeFunctions.isoTime,
});

const orderLogger: OrderLogger = {
  info(message, fields) {
    logger.info(fields, message);
  },
  warn(message, fields) {
    logger.warn(fields, message);
  },
  error(message, fields) {
    logger.error(fields, message);
  },
};

const repository = new PrismaOrderRepository(prisma);

async function publishEvent(event: OrderPlacedEvent): Promise<void> {
  logger.info(
    {
      domain: 'order',
      action: 'order.event_publish',
      trace_id: event.traceId,
      order_id: event.orderId,
      user_id: event.userId,
      event_name: event.type,
      status: event.status,
      total_amount_cents: event.totalAmountCents,
    },
    'order event published',
  );

  // 示例中直接记录日志代替真实消息总线。
  // 生产环境可替换为 Kafka / NATS / Outbox dispatcher。
}

app.use(express.json());
app.use(traceMiddleware);

app.use(
  '/orders',
  createOrderRouter({
    repository,
    publishEvent,
    log: orderLogger,
  }),
);

app.use(
  (
    error: unknown,
    req: Request,
    res: Response,
    _next: NextFunction,
  ) => {
    logger.error(
      {
        domain: 'order',
        action: 'order.system_error',
        trace_id: req.traceId ?? 'unknown',
        order_id: null,
        user_id: readUserId(req.body),
        error_classification: 'system_exception',
        retryable: true,
        err: error,
      },
      'uncaught system error',
    );

    res.status(500).json({
      error: 'INTERNAL_SERVER_ERROR',
      message: '系统异常，请稍后重试',
      traceId: req.traceId ?? 'unknown',
      retryable: true,
    });
  },
);

const port = Number(process.env.PORT ?? 3000);
const server = app.listen(port, () => {
  logger.info(
    {
      domain: 'order',
      action: 'app.started',
      trace_id: 'system',
      order_id: null,
      user_id: null,
      port,
    },
    'http server started',
  );
});

async function shutdown(signal: string): Promise<void> {
  logger.info(
    {
      domain: 'order',
      action: 'app.shutdown',
      trace_id: 'system',
      order_id: null,
      user_id: null,
      signal,
    },
    'shutdown signal received',
  );

  server.close(async () => {
    await prisma.$disconnect();
    process.exit(0);
  });
}

process.on('SIGINT', () => {
  void shutdown('SIGINT');
});

process.on('SIGTERM', () => {
  void shutdown('SIGTERM');
});

function readUserId(body: unknown): string | null {
  if (
    body &&
    typeof body === 'object' &&
    'userId' in body &&
    typeof body.userId === 'string'
  ) {
    return body.userId;
  }

  return null;
}
```

## 说明

- 业务拒绝只抛 `OrderError`，例如用户不存在、用户被封禁、库存不足、重复幂等键
- `saveWithIdempotencyCheck` 在同一笔 Prisma 事务里落订单并写入唯一幂等键，重复键命中后回读原订单结果
- 事件发布放在 `withTransaction` 返回之后，因此一定发生在事务提交之后
- `app/` 没有业务规则，只做 HTTP 字段提取、错误码映射、依赖装配
- 所有关键日志都带 `domain/action/trace_id/order_id/user_id`，便于链路检索
