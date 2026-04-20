# 实现示例：TypeScript + AWS Lambda

本示例沿用 `typescript-node.md` 的 VCDDD PlaceOrder 场景、聚合结构、幂等语义与失败处理规则，只把框架层从 Express 替换为 AWS Lambda。

技术栈：
- TypeScript
- AWS Lambda（`APIGatewayProxyHandlerV2`）
- Prisma
- PostgreSQL
- pino

对应域文档：
- `docs/vcddd/design/order/boundary.md`
- `docs/vcddd/design/order/business.md`

---

## 项目目录

```text
.
├── handler/
│   ├── order.handler.ts              ← Lambda HTTP 入口：解析 API Gateway 事件、调用应用服务、映射 HTTP 响应
│   └── trace.ts                      ← 从 Lambda 事件头提取或生成 trace_id
├── server/
│   └── order/
│       ├── aggregate.ts              ← 订单聚合根：不变式、状态迁移、领域事件收集
│       ├── commands.ts               ← PlaceOrder 命令处理：事务、原子幂等、事件发布、错误分类入口
│       ├── events.ts                 ← 领域事件定义：OrderPlaced、PaymentConfirmed、OrderCancelled
│       ├── repository.ts             ← 仓储接口：事务边界与原子幂等写入结果
│       ├── prisma.repository.ts      ← Prisma 仓储实现：PostgreSQL 事务、原子幂等门闩、Lambda 连接复用
│       └── read_model.ts             ← 读模型：订单读结构
├── prisma/
│   └── schema.prisma                 ← 最小可运行 Prisma schema：`orders`、`order_idempotency`
├── package.json                      ← 最小可运行依赖与脚本
└── tsconfig.json                     ← 最小可运行 TypeScript 编译配置
```

说明：
- `server/order/` 与 Node 版本保持同一层次职责；其中 `prisma.repository.ts` 负责 Prisma 持久化，其余文件不感知 Lambda。
- `handler/` 只负责 HTTP/Lambda 适配，不承载业务规则。
- `server/order/prisma.repository.ts` 用模块级单例 + 懒初始化管理 Prisma Client，复用 Lambda 热启动连接。

---

## server/order/aggregate.ts

```typescript
import { randomUUID } from 'node:crypto';
import { BusinessRejection } from './commands';
import type {
  OrderCancelled,
  OrderDomainEvent,
  OrderPlaced,
  PaymentConfirmed,
} from './events';

export type OrderState =
  | 'PENDING_PAYMENT'
  | 'PENDING_SHIPMENT'
  | 'SHIPPED'
  | 'COMPLETED'
  | 'CANCELLED';

export interface PlaceOrderProps {
  buyerId: string;
  productId: string;
  quantity: number;
  shippingAddress: string;
}

export interface OrderSnapshot {
  orderId: string;
  buyerId: string;
  productId: string;
  quantity: number;
  shippingAddress: string;
  totalAmount: number;
  state: OrderState;
}

export class Order {
  readonly orderId: string;
  readonly buyerId: string;
  readonly productId: string;
  readonly quantity: number;
  readonly shippingAddress: string;
  readonly totalAmount: number;
  private state: OrderState;
  private readonly domainEvents: OrderDomainEvent[];

  private constructor(snapshot: OrderSnapshot, domainEvents: OrderDomainEvent[] = []) {
    this.orderId = snapshot.orderId;
    this.buyerId = snapshot.buyerId;
    this.productId = snapshot.productId;
    this.quantity = snapshot.quantity;
    this.shippingAddress = snapshot.shippingAddress;
    this.totalAmount = snapshot.totalAmount;
    this.state = snapshot.state;
    this.domainEvents = domainEvents;
  }

  static place(props: PlaceOrderProps): Order {
    if (!props.buyerId.trim()) {
      throw new BusinessRejection('INVALID_BUYER', '买家信息不能为空');
    }

    if (!props.productId.trim()) {
      throw new BusinessRejection('INVALID_PRODUCT', '商品信息不能为空');
    }

    if (props.quantity <= 0) {
      throw new BusinessRejection('INVALID_QUANTITY', '订单数量必须大于零');
    }

    if (!props.shippingAddress.trim()) {
      throw new BusinessRejection('INVALID_SHIPPING_ADDRESS', '收货地址不能为空');
    }

    const totalAmount = calculateAmount(props.productId, props.quantity);
    if (totalAmount <= 0) {
      throw new BusinessRejection('INVALID_AMOUNT', '订单金额必须大于零');
    }

    const order = new Order({
      orderId: randomUUID(),
      buyerId: props.buyerId,
      productId: props.productId,
      quantity: props.quantity,
      shippingAddress: props.shippingAddress,
      totalAmount,
      state: 'PENDING_PAYMENT',
    });

    order.record({
      eventId: randomUUID(),
      eventType: 'OrderPlaced',
      orderId: order.orderId,
      buyerId: order.buyerId,
      productId: order.productId,
      quantity: order.quantity,
      totalAmount: order.totalAmount,
    });

    return order;
  }

  static rehydrate(snapshot: OrderSnapshot): Order {
    return new Order(snapshot);
  }

  confirmPayment(): PaymentConfirmed {
    if (this.state !== 'PENDING_PAYMENT') {
      throw new BusinessRejection(
        'INVALID_STATE_TRANSITION',
        `当前订单状态为 ${this.state}，不允许执行支付确认`
      );
    }

    this.state = 'PENDING_SHIPMENT';

    const event: PaymentConfirmed = {
      eventId: randomUUID(),
      eventType: 'PaymentConfirmed',
      orderId: this.orderId,
    };

    this.record(event);
    return event;
  }

  cancel(): OrderCancelled {
    if (this.state === 'SHIPPED' || this.state === 'COMPLETED') {
      throw new BusinessRejection('ORDER_NOT_CANCELLABLE', '订单已发货，不可撤销');
    }
    if (this.state === 'CANCELLED') {
      throw new BusinessRejection('ORDER_ALREADY_CANCELLED', '订单已取消');
    }

    this.state = 'CANCELLED';

    const event: OrderCancelled = {
      eventId: randomUUID(),
      eventType: 'OrderCancelled',
      orderId: this.orderId,
    };

    this.record(event);
    return event;
  }

  getState(): OrderState {
    return this.state;
  }

  snapshot(): OrderSnapshot {
    return {
      orderId: this.orderId,
      buyerId: this.buyerId,
      productId: this.productId,
      quantity: this.quantity,
      shippingAddress: this.shippingAddress,
      totalAmount: this.totalAmount,
      state: this.state,
    };
  }

  pullDomainEvents(): OrderDomainEvent[] {
    const events = [...this.domainEvents];
    this.domainEvents.length = 0;
    return events;
  }

  private record(event: OrderDomainEvent): void {
    this.domainEvents.push(event);
  }
}

function calculateAmount(productId: string, quantity: number): number {
  const priceTable: Record<string, number> = {
    'product-basic': 19900,
    'product-premium': 39900,
  };

  const unitPrice = priceTable[productId] ?? 19900;
  return unitPrice * quantity;
}
```

---

## server/order/commands.ts

```typescript
import { Order } from './aggregate';
import type { OrderPlaced } from './events';
import type { OrderRepository } from './repository';

export interface PlaceOrderCommand {
  commandId: string;
  buyerId: string;
  productId: string;
  quantity: number;
  shippingAddress: string;
}

export interface PlaceOrderResult {
  orderId: string;
  deduplicated: boolean;
}

export interface AppLogger {
  info(bindings: Record<string, unknown>, message: string): void;
  warn(bindings: Record<string, unknown>, message: string): void;
  error(bindings: Record<string, unknown>, message: string): void;
}

export interface PublishedOrderPlaced extends OrderPlaced {
  traceId: string;
  occurredAt: string;
}

export interface HandlePlaceOrderDeps {
  repository: OrderRepository;
  logger: AppLogger;
  traceId: string;
  publishEvent: (event: PublishedOrderPlaced) => Promise<void>;
  now?: () => Date;
}

export class BusinessRejection extends Error {
  constructor(
    public readonly code: string,
    message: string
  ) {
    super(message);
    this.name = 'BusinessRejection';
  }
}

export async function handlePlaceOrder(
  command: PlaceOrderCommand,
  deps: HandlePlaceOrderDeps
): Promise<PlaceOrderResult> {
  validateCommand(command);

  const order = Order.place({
    buyerId: command.buyerId,
    productId: command.productId,
    quantity: command.quantity,
    shippingAddress: command.shippingAddress,
  });

  const [placedEvent] = order.pullDomainEvents();

  const result = await deps.repository.withTransaction(async (tx) => {
    const persisted = await tx.saveWithCommandId(order, command.commandId);

    if (persisted.deduplicated) {
      deps.logger.info(
        {
          command_id: command.commandId,
          existing_order_id: persisted.orderId,
        },
        'PlaceOrder 幂等命中，返回首次成功结果'
      );
      return persisted;
    }

    deps.logger.info(
      {
        order_id: order.orderId,
        from_state: '（新建）',
        to_state: 'PENDING_PAYMENT',
        trigger: 'PlaceOrder',
      },
      '订单状态迁移完成'
    );

    return persisted;
  });

  if (!result.deduplicated && placedEvent?.eventType === 'OrderPlaced') {
    const event: PublishedOrderPlaced = {
      ...placedEvent,
      traceId: deps.traceId,
      occurredAt: (deps.now ?? (() => new Date()))().toISOString(),
    };

    try {
      await deps.publishEvent(event);
      deps.logger.info(
        {
          event_id: event.eventId,
          order_id: event.orderId,
        },
        'OrderPlaced 事件已发布'
      );
    } catch (error) {
      deps.logger.error(
        {
          event_id: event.eventId,
          order_id: event.orderId,
          error: serializeError(error),
          error_classification: 'integration',
          retryable: true,
        },
        'OrderPlaced 事件发布失败，订单已提交，交由异步重试'
      );
    }
  }

  return result;
}

function validateCommand(command: PlaceOrderCommand): void {
  if (!command.commandId?.trim()) {
    throw new BusinessRejection('INVALID_COMMAND_ID', 'commandId 不能为空');
  }
}

function serializeError(error: unknown): Record<string, unknown> {
  if (error instanceof Error) {
    return {
      name: error.name,
      message: error.message,
    };
  }

  return {
    message: String(error),
  };
}
```

---

## server/order/events.ts

```typescript
export interface OrderPlaced {
  eventId: string;
  eventType: 'OrderPlaced';
  orderId: string;
  buyerId: string;
  productId: string;
  quantity: number;
  totalAmount: number;
}

export interface PaymentConfirmed {
  eventId: string;
  eventType: 'PaymentConfirmed';
  orderId: string;
}

export interface OrderCancelled {
  eventId: string;
  eventType: 'OrderCancelled';
  orderId: string;
}

export type OrderDomainEvent =
  | OrderPlaced
  | PaymentConfirmed
  | OrderCancelled;
```

---

## server/order/repository.ts

```typescript
import type { Order } from './aggregate';
import type { OrderReadModel } from './read_model';

export interface SaveWithCommandIdResult {
  orderId: string;
  deduplicated: boolean;
}

export interface OrderTransaction {
  saveWithCommandId(
    order: Order,
    commandId: string
  ): Promise<SaveWithCommandIdResult>;
  findOrderById(orderId: string): Promise<OrderReadModel | null>;
}

export interface OrderRepository {
  withTransaction<T>(fn: (tx: OrderTransaction) => Promise<T>): Promise<T>;
}
```

---

## server/order/read_model.ts

```typescript
import type { OrderState } from './aggregate';

export interface OrderReadModel {
  orderId: string;
  buyerId: string;
  productId: string;
  quantity: number;
  shippingAddress: string;
  totalAmount: number;
  state: OrderState;
  createdAt: string;
  updatedAt: string;
}
```

---

## handler/trace.ts

```typescript
import { randomUUID } from 'node:crypto';
import type { APIGatewayProxyEventV2 } from 'aws-lambda';

const TRACE_HEADER_CANDIDATES = [
  'x-trace-id',
  'x-request-id',
  'x-correlation-id',
];

export function extractTraceId(
  event: Pick<APIGatewayProxyEventV2, 'headers' | 'requestContext'>
): string {
  const normalizedHeaders = Object.fromEntries(
    Object.entries(event.headers ?? {}).map(([key, value]) => [
      key.toLowerCase(),
      value?.trim(),
    ])
  );

  for (const headerName of TRACE_HEADER_CANDIDATES) {
    const traceId = normalizedHeaders[headerName];
    if (traceId) {
      return traceId;
    }
  }

  if (event.requestContext.requestId?.trim()) {
    return event.requestContext.requestId;
  }

  return randomUUID();
}
```

---

## handler/order.handler.ts

```typescript
import type {
  APIGatewayProxyEventV2,
  APIGatewayProxyHandlerV2,
  APIGatewayProxyResultV2,
  Context,
} from 'aws-lambda';
import pino from 'pino';
import {
  BusinessRejection,
  handlePlaceOrder,
  type PlaceOrderCommand,
} from '../server/order/commands';
import { PrismaOrderRepository } from '../server/order/prisma.repository';
import { extractTraceId } from './trace';

const rootLogger = pino({
  level: process.env.LOG_LEVEL ?? 'info',
  base: undefined,
  timestamp: pino.stdTimeFunctions.isoTime,
});

// 模块级实例在 Lambda 热启动时会被复用，内部 Prisma Client 仍然是懒初始化。
const repository = new PrismaOrderRepository();

export const placeOrderHandler: APIGatewayProxyHandlerV2 = async (
  event: APIGatewayProxyEventV2,
  context: Context
): Promise<APIGatewayProxyResultV2> => {
  // 允许 Lambda 在连接仍保持打开时提前返回，避免等待数据库连接池清空。
  context.callbackWaitsForEmptyEventLoop = false;

  const traceId = extractTraceId(event);
  const logger = rootLogger.child({
    domain: 'order',
    action: 'place_order',
    trace_id: traceId,
    aws_request_id: context.awsRequestId,
    route_key: event.requestContext.routeKey ?? 'POST /orders',
  });

  let command: PlaceOrderCommand;
  try {
    command = parseCommand(event);
  } catch (error) {
    logger.warn(
      {
        error: serializeError(error),
        error_classification: 'client',
        retryable: false,
      },
      'PlaceOrder 请求体解析失败'
    );
    return json(
      400,
      {
        errorCode: 'INVALID_JSON',
        message: '请求体不是合法 JSON',
      },
      traceId
    );
  }

  logger.info(
    {
      command_id: command.commandId,
      buyer_id: command.buyerId,
      product_id: command.productId,
      quantity: command.quantity,
    },
    'PlaceOrder 命令已接收'
  );

  try {
    const result = await handlePlaceOrder(command, {
      repository,
      logger,
      traceId,
      publishEvent: async (domainEvent) => {
        // 示例中省略真实事件总线实现，保留事务提交后发布的时序。
        logger.info(
          {
            event_id: domainEvent.eventId,
            event_type: domainEvent.eventType,
            order_id: domainEvent.orderId,
          },
          '发布领域事件到事件总线'
        );
      },
    });

    logger.info(
      {
        command_id: command.commandId,
        order_id: result.orderId,
        deduplicated: result.deduplicated,
      },
      'PlaceOrder 命令执行成功'
    );

    return json(
      201,
      {
        orderId: result.orderId,
      },
      traceId
    );
  } catch (error) {
    if (error instanceof BusinessRejection) {
      logger.warn(
        {
          command_id: command.commandId,
          reason: error.code,
          detail: error.message,
          error_classification: 'business',
          retryable: false,
        },
        'PlaceOrder 被业务规则拒绝'
      );

      return json(
        422,
        {
          errorCode: error.code,
          message: error.message,
        },
        traceId
      );
    }

    logger.error(
      {
        command_id: command.commandId,
        error: serializeError(error),
        error_classification: 'system',
        retryable: true,
      },
      'PlaceOrder 发生系统异常'
    );

    return json(
      500,
      {
        errorCode: 'SYSTEM_ERROR',
        message: '系统暂时不可用，请重试',
      },
      traceId
    );
  }
};

function parseCommand(event: APIGatewayProxyEventV2): PlaceOrderCommand {
  if (!event.body) {
    throw new Error('empty body');
  }

  const rawBody = event.isBase64Encoded
    ? Buffer.from(event.body, 'base64').toString('utf8')
    : event.body;

  return JSON.parse(rawBody) as PlaceOrderCommand;
}

function json(
  statusCode: number,
  body: Record<string, unknown>,
  traceId: string
): APIGatewayProxyResultV2 {
  return {
    statusCode,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'x-trace-id': traceId,
    },
    body: JSON.stringify(body),
  };
}

function serializeError(error: unknown): Record<string, unknown> {
  if (error instanceof Error) {
    return {
      name: error.name,
      message: error.message,
      stack: error.stack,
    };
  }

  return {
    message: String(error),
  };
}
```

---

## server/order/prisma.repository.ts

```typescript
import { Prisma, PrismaClient } from '@prisma/client';
import type { Order } from './aggregate';
import type {
  OrderRepository,
  OrderTransaction,
  SaveWithCommandIdResult,
} from './repository';
import type { OrderReadModel } from './read_model';

let prismaClient: PrismaClient | undefined;

function getPrismaClient(): PrismaClient {
  if (!prismaClient) {
    prismaClient = new PrismaClient({
      log: process.env.NODE_ENV === 'development' ? ['warn', 'error'] : ['error'],
    });
  }

  return prismaClient;
}

export class PrismaOrderRepository implements OrderRepository {
  constructor(
    private readonly prismaFactory: () => PrismaClient = getPrismaClient
  ) {}

  async withTransaction<T>(fn: (tx: OrderTransaction) => Promise<T>): Promise<T> {
    return this.prismaFactory().$transaction(
      async (transaction) => fn(new PrismaOrderTransaction(transaction)),
      {
        isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
        maxWait: 5_000,
        timeout: 10_000,
      }
    );
  }
}

class PrismaOrderTransaction implements OrderTransaction {
  constructor(private readonly tx: Prisma.TransactionClient) {}

  async saveWithCommandId(
    order: Order,
    commandId: string
  ): Promise<SaveWithCommandIdResult> {
    const snapshot = order.snapshot();
    const now = new Date();

    const gate = await this.tx.orderIdempotency.createMany({
      data: [
        {
          commandId,
          orderId: snapshot.orderId,
          createdAt: now,
        },
      ],
      skipDuplicates: true,
    });

    if (gate.count === 0) {
      const existing = await this.tx.orderIdempotency.findUnique({
        where: { commandId },
        select: {
          orderId: true,
        },
      });

      if (!existing) {
        throw new Error(`commandId=${commandId} 的幂等记录读取失败`);
      }

      return {
        orderId: existing.orderId,
        deduplicated: true,
      };
    }

    await this.tx.order.create({
      data: {
        orderId: snapshot.orderId,
        buyerId: snapshot.buyerId,
        productId: snapshot.productId,
        quantity: snapshot.quantity,
        shippingAddress: snapshot.shippingAddress,
        totalAmount: snapshot.totalAmount,
        state: snapshot.state,
        createdAt: now,
        updatedAt: now,
      },
    });

    return {
      orderId: snapshot.orderId,
      deduplicated: false,
    };
  }

  async findOrderById(orderId: string): Promise<OrderReadModel | null> {
    const row = await this.tx.order.findUnique({
      where: { orderId },
    });

    if (!row) {
      return null;
    }

    return {
      orderId: row.orderId,
      buyerId: row.buyerId,
      productId: row.productId,
      quantity: row.quantity,
      shippingAddress: row.shippingAddress,
      totalAmount: row.totalAmount,
      state: row.state,
      createdAt: row.createdAt.toISOString(),
      updatedAt: row.updatedAt.toISOString(),
    };
  }
}
```

---

## prisma/schema.prisma

```prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model Order {
  orderId         String   @id @map("order_id")
  buyerId         String   @map("buyer_id")
  productId       String   @map("product_id")
  quantity        Int
  shippingAddress String   @map("shipping_address")
  totalAmount     Int      @map("total_amount")
  state           String
  createdAt       DateTime @map("created_at")
  updatedAt       DateTime @map("updated_at")

  @@map("orders")
}

model OrderIdempotency {
  commandId String   @id @map("command_id")
  orderId   String   @map("order_id")
  createdAt DateTime @map("created_at")

  @@map("order_idempotency")
}
```

---

## package.json

```json
{
  "name": "vcddd-typescript-serverless-example",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "prisma:generate": "prisma generate"
  },
  "dependencies": {
    "@prisma/client": "^6.6.0",
    "pino": "^9.3.2"
  },
  "devDependencies": {
    "@types/aws-lambda": "^8.10.147",
    "@types/node": "^22.15.3",
    "prisma": "^6.6.0",
    "typescript": "^5.8.3"
  }
}
```

---

## tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "strict": true,
    "esModuleInterop": true,
    "forceConsistentCasingInFileNames": true,
    "skipLibCheck": true,
    "outDir": "dist",
    "rootDir": ".",
    "types": ["node", "aws-lambda"]
  },
  "include": ["handler/**/*.ts", "server/**/*.ts"]
}
```

---

## 失败路径总结

| 失败场景 | 捕获位置 | 处理方式 | 是否回滚 | 错误响应 |
|----------|----------|----------|----------|----------|
| 数量 ≤ 0 | `Order.place()` | 抛出 `BusinessRejection` | 事务回滚 | `422 + INVALID_QUANTITY` |
| 金额 ≤ 0 | `Order.place()` | 抛出 `BusinessRejection` | 事务回滚 | `422 + INVALID_AMOUNT` |
| 幂等命中 | `saveWithCommandId()` 原子写入 `order_idempotency` 门闩 | 不抛异常，直接读回首次结果 | 无新写入 | `201 + 原 orderId` |
| PostgreSQL / Prisma 写入失败 | `saveWithCommandId()` | 抛出系统异常，上层记录错误 | 事务自动回滚 | `500 + SYSTEM_ERROR` |
| 事件发布失败 | `handlePlaceOrder()` 提交后发布 | 记录错误日志，交给异步重试机制 | 订单已保存，不回滚 | `201 + orderId` |

---

## Lambda 中的 Prisma 连接管理

关键点：
- `prismaClient` 定义在模块作用域，冷启动时为空，首次访问 `getPrismaClient()` 才真正创建连接。
- `PrismaOrderRepository` 依赖 `prismaFactory`，即使仓储实例在模块级复用，也不会在 import 阶段强制建连。
- Lambda 热启动会复用同一个 Node.js 进程，模块作用域中的 `prismaClient` 因此会被重复利用。
- `context.callbackWaitsForEmptyEventLoop = false` 允许处理函数在连接池保持打开时返回，避免 Lambda 因事件循环未清空而延迟结束。
- 示例代码使用 `APIGatewayProxyResultV2`，其返回字段与常见的 `APIGatewayProxyResult` JSON 响应结构一致。

最小示意：

```typescript
let prismaClient: PrismaClient | undefined;

function getPrismaClient(): PrismaClient {
  if (!prismaClient) {
    prismaClient = new PrismaClient();
  }
  return prismaClient;
}

const repository = new PrismaOrderRepository(getPrismaClient);
```

这套写法满足两个目标：
- 冷启动时只初始化一次。
- 热启动时复用已有 Prisma Client，不在每次请求都重新建连。

---

## 关键技术决策

| 决策点 | 选择方案 | 选择原因 | 被否定的方案 | 否定原因 |
|--------|----------|----------|--------------|----------|
| 框架层入口 | `APIGatewayProxyHandlerV2` + `handler/order.handler.ts` | 明确隔离 HTTP 适配与领域命令处理 | 在 `server/order/commands.ts` 直接依赖 Lambda 事件类型 | 破坏分层，领域层与运行时强耦合 |
| 幂等实现 | 原子写入 `order_idempotency` 门闩，命中后读回首次结果 | 消除 check-then-insert，并发重复请求直接复用第一次成功响应 | 只做应用层先查后写 | 非原子，并发时可能重复创建订单 |
| 事务边界 | `OrderRepository.withTransaction()` | 事务留在仓储层，应用服务不感知 Prisma 细节 | 在 Handler 中直接写 Prisma 事务 | 框架层泄漏领域持久化细节 |
| 事件发布时机 | 事务提交后发布，失败仅记录日志 | 保证“订单已提交”与“事件可补偿重试”语义 | 在事务内发布事件 | 数据回滚后事件无法撤回 |
| Lambda 连接管理 | 模块级单例 + 懒初始化 Prisma Client | 冷启动只建连一次，热启动可复用 | 每次调用新建 `PrismaClient()` | 连接抖动大，容易放大数据库压力 |
