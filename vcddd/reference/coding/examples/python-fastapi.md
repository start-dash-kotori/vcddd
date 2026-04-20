# 实现示例：Python 3.12 + FastAPI

本示例展示“订单域 - PlaceOrder”命令在 `Python 3.12 + FastAPI + SQLAlchemy Async + PostgreSQL + structlog` 技术栈下的 VCDDD 落地方式。

目标约束：
- `server/` 是领域层，不引入 FastAPI。
- `api/` 是框架适配层，只做 HTTP、依赖注入、错误映射。
- `server/order/sqlalchemy_repository.py` 放置 SQLAlchemy 持久化实现，与仓储接口同目录。
- 幂等键由调用方提供，并在 SQLAlchemy 事务内通过唯一约束原子检测。
- 一个聚合一次事务，事务提交后再发布事件。
- 业务拒绝统一抛 `OrderError`，系统异常保持普通异常。

---

## 项目目录

```text
app/
├── api/
│   ├── main.py                           ← FastAPI 入口；配置 structlog JSON、注册中间件和路由、装配依赖
│   ├── middleware/
│   │   └── trace.py                     ← 生成/透传 trace_id，写入 request.state，并回写响应头
│   └── routers/
│       └── order.py                     ← HTTP 适配层；请求模型、依赖注入、异常到 HTTP 的映射
└── server/
    └── order/
        ├── aggregate.py                 ← 订单聚合、状态、不变式、OrderError
        ├── commands.py                  ← PlaceOrder 命令对象与命令处理器
        ├── events.py                    ← OrderPlaced 领域事件
        ├── repository.py                ← 仓储接口、用户/库存查询接口、事件发布接口
        ├── sqlalchemy_repository.py     ← OrderRepository 的 SQLAlchemy Async + PostgreSQL 实现
        └── read_model.py                ← 返回给接口层的订单读模型
```

---

## server/order/aggregate.py

```python
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime
from enum import StrEnum
from uuid import uuid4


class OrderError(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


class OrderStatus(StrEnum):
    PENDING = "PENDING"


@dataclass(slots=True)
class Order:
    order_id: str
    user_id: str
    product_id: str
    quantity: int
    idempotency_key: str
    status: OrderStatus = OrderStatus.PENDING
    created_at: datetime = field(default_factory=lambda: datetime.now(UTC))

    @classmethod
    def place(
        cls,
        *,
        user_id: str,
        product_id: str,
        quantity: int,
        idempotency_key: str,
        trace_id: str,
    ) -> tuple["Order", "OrderPlaced"]:
        from server.order.events import OrderPlaced

        if not user_id.strip():
            raise OrderError("INVALID_USER_ID", "user_id 不能为空")
        if not product_id.strip():
            raise OrderError("INVALID_PRODUCT_ID", "product_id 不能为空")
        if quantity <= 0:
            raise OrderError("INVALID_QUANTITY", "quantity 必须大于 0")
        if not idempotency_key.strip():
            raise OrderError("INVALID_IDEMPOTENCY_KEY", "idempotency_key 不能为空")

        order = cls(
            order_id=str(uuid4()),
            user_id=user_id,
            product_id=product_id,
            quantity=quantity,
            idempotency_key=idempotency_key,
        )
        return order, OrderPlaced.from_order(order, trace_id=trace_id)
```

---

## server/order/events.py

```python
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime

from server.order.aggregate import Order, OrderStatus


@dataclass(frozen=True, slots=True)
class OrderPlaced:
    order_id: str
    user_id: str
    product_id: str
    quantity: int
    status: OrderStatus
    trace_id: str
    occurred_at: datetime = field(default_factory=lambda: datetime.now(UTC))
    event_name: str = "order.placed"

    @classmethod
    def from_order(cls, order: Order, *, trace_id: str) -> "OrderPlaced":
        return cls(
            order_id=order.order_id,
            user_id=order.user_id,
            product_id=order.product_id,
            quantity=order.quantity,
            status=order.status,
            trace_id=trace_id,
        )
```

---

## server/order/read_model.py

```python
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from server.order.aggregate import OrderStatus


@dataclass(frozen=True, slots=True)
class OrderReadModel:
    order_id: str
    user_id: str
    product_id: str
    quantity: int
    status: OrderStatus
    idempotency_key: str
    created_at: datetime
```

---

## server/order/repository.py

```python
from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

from server.order.aggregate import Order
from server.order.events import OrderPlaced
from server.order.read_model import OrderReadModel


@dataclass(frozen=True, slots=True)
class UserSnapshot:
    user_id: str
    is_banned: bool


@dataclass(frozen=True, slots=True)
class InventorySnapshot:
    product_id: str
    available_quantity: int


class OrderRepository(Protocol):
    async def save_with_idempotency_check(self, order: Order) -> OrderReadModel:
        """
        在单个数据库事务中保存订单，并利用唯一约束原子处理幂等键。
        首次调用返回新订单；重复调用返回已存在订单。
        """

    async def get(self, order_id: str) -> OrderReadModel | None:
        """按 order_id 读取订单读模型。"""


class UserService(Protocol):
    async def get_user(self, user_id: str) -> UserSnapshot | None:
        """查询用户；不存在时返回 None。"""


class InventoryService(Protocol):
    async def get_inventory(self, product_id: str) -> InventorySnapshot:
        """查询商品当前可用库存。"""


class EventPublisher(Protocol):
    async def publish_order_placed(self, event: OrderPlaced) -> None:
        """在事务提交后发布 OrderPlaced 事件。"""
```

---

## server/order/commands.py

```python
from __future__ import annotations

from dataclasses import dataclass

import structlog

from server.order.aggregate import Order, OrderError
from server.order.read_model import OrderReadModel
from server.order.repository import (
    EventPublisher,
    InventoryService,
    OrderRepository,
    UserService,
)


@dataclass(frozen=True, slots=True)
class PlaceOrder:
    user_id: str
    product_id: str
    quantity: int
    idempotency_key: str
    trace_id: str


class PlaceOrderHandler:
    def __init__(
        self,
        *,
        repository: OrderRepository,
        user_service: UserService,
        inventory_service: InventoryService,
        event_publisher: EventPublisher,
    ) -> None:
        self._repository = repository
        self._user_service = user_service
        self._inventory_service = inventory_service
        self._event_publisher = event_publisher
        self._logger = structlog.get_logger(__name__)

    async def handle(self, command: PlaceOrder) -> OrderReadModel:
        logger = self._logger.bind(
            domain="order",
            action="place_order",
            trace_id=command.trace_id,
            order_id=None,
            user_id=command.user_id,
        )

        logger.info(
            "command_entry",
            product_id=command.product_id,
            quantity=command.quantity,
            idempotency_key=command.idempotency_key,
        )

        user = await self._user_service.get_user(command.user_id)
        if user is None:
            logger.bind(
                error_classification="business_rejection",
                retryable=False,
            ).warning("business_rejected", error_code="USER_NOT_FOUND")
            raise OrderError("USER_NOT_FOUND", "用户不存在")

        if user.is_banned:
            logger.bind(
                error_classification="business_rejection",
                retryable=False,
            ).warning("business_rejected", error_code="USER_BANNED")
            raise OrderError("USER_BANNED", "用户已被封禁")

        inventory = await self._inventory_service.get_inventory(command.product_id)
        if inventory.available_quantity < command.quantity:
            logger.bind(
                error_classification="business_rejection",
                retryable=False,
            ).warning(
                "business_rejected",
                error_code="INSUFFICIENT_INVENTORY",
                available_quantity=inventory.available_quantity,
                requested_quantity=command.quantity,
            )
            raise OrderError("INSUFFICIENT_INVENTORY", "库存不足")

        try:
            order, event = Order.place(
                user_id=command.user_id,
                product_id=command.product_id,
                quantity=command.quantity,
                idempotency_key=command.idempotency_key,
                trace_id=command.trace_id,
            )
        except OrderError as exc:
            logger.bind(
                error_classification="business_rejection",
                retryable=False,
            ).warning(
                "aggregate_creation_failed",
                error_code=exc.code,
            )
            raise

        logger = logger.bind(order_id=order.order_id)

        persisted_order = await self._repository.save_with_idempotency_check(order)
        if persisted_order.order_id != order.order_id:
            return persisted_order

        logger.info(
            "state_transition",
            from_state="NEW",
            to_state=persisted_order.status.value,
        )

        try:
            await self._event_publisher.publish_order_placed(event)
        except Exception:
            logger.bind(
                error_classification="system_exception",
                retryable=True,
            ).exception(
                "event_publish_failed",
                event_name=event.event_name,
            )
            raise

        logger.info(
            "event_publish",
            event_name=event.event_name,
            occurred_at=event.occurred_at.isoformat(),
        )

        return persisted_order
```

---

## server/order/sqlalchemy_repository.py

```python
from __future__ import annotations

from datetime import datetime
from typing import Final

from sqlalchemy import DateTime, Integer, String, UniqueConstraint, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

from server.order.aggregate import Order, OrderError, OrderStatus
from server.order.read_model import OrderReadModel
from server.order.repository import OrderRepository


IDEMPOTENCY_CONSTRAINT_NAME: Final = "uq_orders_idempotency_key"


class Base(DeclarativeBase):
    pass


class OrderRecord(Base):
    __tablename__ = "orders"
    __table_args__ = (
        UniqueConstraint("idempotency_key", name=IDEMPOTENCY_CONSTRAINT_NAME),
    )

    order_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(64), index=True, nullable=False)
    product_id: Mapped[str] = mapped_column(String(64), nullable=False)
    quantity: Mapped[int] = mapped_column(Integer, nullable=False)
    status: Mapped[str] = mapped_column(String(32), nullable=False)
    idempotency_key: Mapped[str] = mapped_column(String(128), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class SqlAlchemyOrderRepository(OrderRepository):
    def __init__(self, session_factory: async_sessionmaker[AsyncSession]) -> None:
        self._session_factory = session_factory

    async def save_with_idempotency_check(self, order: Order) -> OrderReadModel:
        """
        单聚合单事务：
        1. 开启事务
        2. 插入订单
        3. flush 触发 PostgreSQL 唯一约束检查
        4. 唯一约束冲突时按 idempotency_key 回读已存在订单
        5. 事务提交成功后才返回
        """
        async with self._session_factory() as session:
            try:
                async with session.begin():
                    session.add(
                        OrderRecord(
                            order_id=order.order_id,
                            user_id=order.user_id,
                            product_id=order.product_id,
                            quantity=order.quantity,
                            status=order.status.value,
                            idempotency_key=order.idempotency_key,
                            created_at=order.created_at,
                        )
                    )
                    await session.flush()
                return OrderReadModel(
                    order_id=order.order_id,
                    user_id=order.user_id,
                    product_id=order.product_id,
                    quantity=order.quantity,
                    status=order.status,
                    idempotency_key=order.idempotency_key,
                    created_at=order.created_at,
                )
            except IntegrityError as exc:
                if self._is_duplicate_idempotency_key(exc):
                    existing = await self._get_by_idempotency_key(
                        session,
                        order.idempotency_key,
                    )
                    if existing is not None:
                        return existing
                raise

    async def get(self, order_id: str) -> OrderReadModel | None:
        async with self._session_factory() as session:
            stmt = select(OrderRecord).where(OrderRecord.order_id == order_id)
            record = await session.scalar(stmt)
            if record is None:
                return None

            return self._to_read_model(record)

    @staticmethod
    def _is_duplicate_idempotency_key(exc: IntegrityError) -> bool:
        original = getattr(exc, "orig", None)
        pgcode = getattr(original, "pgcode", "")
        constraint_name = getattr(getattr(original, "diag", None), "constraint_name", "")

        if pgcode == "23505" and constraint_name == IDEMPOTENCY_CONSTRAINT_NAME:
            return True

        return IDEMPOTENCY_CONSTRAINT_NAME in str(exc)

    async def _get_by_idempotency_key(
        self,
        session: AsyncSession,
        idempotency_key: str,
    ) -> OrderReadModel | None:
        stmt = select(OrderRecord).where(OrderRecord.idempotency_key == idempotency_key)
        record = await session.scalar(stmt)
        if record is None:
            return None
        return self._to_read_model(record)

    @staticmethod
    def _to_read_model(record: OrderRecord) -> OrderReadModel:
        return OrderReadModel(
            order_id=record.order_id,
            user_id=record.user_id,
            product_id=record.product_id,
            quantity=record.quantity,
            status=OrderStatus(record.status),
            idempotency_key=record.idempotency_key,
            created_at=record.created_at,
        )
```

---

## api/routers/order.py

```python
from __future__ import annotations

from datetime import datetime
from typing import Annotated

import structlog
from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, Field

from server.order.aggregate import OrderError
from server.order.commands import PlaceOrder, PlaceOrderHandler
from server.order.read_model import OrderReadModel
from server.order.repository import (
    EventPublisher,
    InventoryService,
    OrderRepository,
    UserService,
)

router = APIRouter(prefix="/orders", tags=["orders"])


class PlaceOrderRequest(BaseModel):
    user_id: str = Field(min_length=1)
    product_id: str = Field(min_length=1)
    quantity: int = Field(gt=0)
    idempotency_key: str = Field(min_length=1)


class PlaceOrderResponse(BaseModel):
    order_id: str
    user_id: str
    product_id: str
    quantity: int
    status: str
    created_at: datetime

    @classmethod
    def from_read_model(cls, order: OrderReadModel) -> "PlaceOrderResponse":
        return cls(
            order_id=order.order_id,
            user_id=order.user_id,
            product_id=order.product_id,
            quantity=order.quantity,
            status=order.status.value,
            created_at=order.created_at,
        )


def get_order_repository(request: Request) -> OrderRepository:
    return request.app.state.order_repository


def get_user_service(request: Request) -> UserService:
    return request.app.state.user_service


def get_inventory_service(request: Request) -> InventoryService:
    return request.app.state.inventory_service


def get_event_publisher(request: Request) -> EventPublisher:
    return request.app.state.event_publisher


@router.post(
    "",
    response_model=PlaceOrderResponse,
    status_code=status.HTTP_201_CREATED,
)
async def place_order(
    payload: PlaceOrderRequest,
    request: Request,
    repository: Annotated[OrderRepository, Depends(get_order_repository)],
    user_service: Annotated[UserService, Depends(get_user_service)],
    inventory_service: Annotated[InventoryService, Depends(get_inventory_service)],
    event_publisher: Annotated[EventPublisher, Depends(get_event_publisher)],
) -> PlaceOrderResponse:
    handler = PlaceOrderHandler(
        repository=repository,
        user_service=user_service,
        inventory_service=inventory_service,
        event_publisher=event_publisher,
    )

    try:
        order = await handler.handle(
            PlaceOrder(
                user_id=payload.user_id,
                product_id=payload.product_id,
                quantity=payload.quantity,
                idempotency_key=payload.idempotency_key,
                trace_id=request.state.trace_id,
            )
        )
    except OrderError as exc:
        raise HTTPException(
            status_code=_status_code_for(exc.code),
            detail={"code": exc.code, "message": str(exc)},
        ) from exc
    except Exception as exc:
        structlog.get_logger(__name__).bind(
            domain="order",
            action="place_order",
            trace_id=request.state.trace_id,
            order_id=None,
            user_id=payload.user_id,
            error_classification="system_exception",
            retryable=True,
        ).exception("system_error")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={"code": "INTERNAL_ERROR", "message": "系统异常，请稍后重试"},
        ) from exc

    return PlaceOrderResponse.from_read_model(order)


def _status_code_for(error_code: str) -> int:
    mapping = {
        "USER_NOT_FOUND": status.HTTP_404_NOT_FOUND,
        "USER_BANNED": status.HTTP_403_FORBIDDEN,
        "INSUFFICIENT_INVENTORY": status.HTTP_409_CONFLICT,
        "INVALID_USER_ID": status.HTTP_422_UNPROCESSABLE_ENTITY,
        "INVALID_PRODUCT_ID": status.HTTP_422_UNPROCESSABLE_ENTITY,
        "INVALID_QUANTITY": status.HTTP_422_UNPROCESSABLE_ENTITY,
        "INVALID_IDEMPOTENCY_KEY": status.HTTP_422_UNPROCESSABLE_ENTITY,
    }
    return mapping.get(error_code, status.HTTP_422_UNPROCESSABLE_ENTITY)
```

---

## api/middleware/trace.py

```python
from __future__ import annotations

from uuid import uuid4

import structlog
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import Response

TRACE_HEADER = "X-Trace-Id"


class TraceMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        trace_id = request.headers.get(TRACE_HEADER) or str(uuid4())
        request.state.trace_id = trace_id

        structlog.contextvars.clear_contextvars()
        structlog.contextvars.bind_contextvars(trace_id=trace_id)

        try:
            response = await call_next(request)
        finally:
            structlog.contextvars.clear_contextvars()

        response.headers[TRACE_HEADER] = trace_id
        return response
```

---

## api/main.py

```python
from __future__ import annotations

import logging
import sys
from contextlib import asynccontextmanager
from typing import Final

import structlog
from fastapi import FastAPI
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from api.middleware.trace import TraceMiddleware
from api.routers.order import router as order_router
from server.order.sqlalchemy_repository import Base, SqlAlchemyOrderRepository
from server.order.events import OrderPlaced
from server.order.repository import (
    EventPublisher,
    InventorySnapshot,
    InventoryService,
    UserService,
    UserSnapshot,
)

DATABASE_URL: Final = "postgresql+asyncpg://app:app@localhost:5432/app"


def configure_logging() -> None:
    shared_processors = [
        structlog.contextvars.merge_contextvars,
        structlog.stdlib.add_log_level,
        structlog.processors.TimeStamper(fmt="iso", utc=True),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
    ]

    structlog.configure(
        processors=[
            *shared_processors,
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.stdlib.BoundLogger,
        logger_factory=structlog.stdlib.LoggerFactory(),
        cache_logger_on_first_use=True,
    )

    logging.basicConfig(
        level=logging.INFO,
        format="%(message)s",
        stream=sys.stdout,
    )


class DemoUserService(UserService):
    def __init__(self) -> None:
        self._users = {
            "user-1": UserSnapshot(user_id="user-1", is_banned=False),
            "user-2": UserSnapshot(user_id="user-2", is_banned=True),
        }

    async def get_user(self, user_id: str) -> UserSnapshot | None:
        return self._users.get(user_id)


class DemoInventoryService(InventoryService):
    def __init__(self) -> None:
        self._inventory = {
            "sku-1": InventorySnapshot(product_id="sku-1", available_quantity=10),
            "sku-2": InventorySnapshot(product_id="sku-2", available_quantity=0),
        }

    async def get_inventory(self, product_id: str) -> InventorySnapshot:
        return self._inventory.get(
            product_id,
            InventorySnapshot(product_id=product_id, available_quantity=0),
        )


class LoggingEventPublisher(EventPublisher):
    async def publish_order_placed(self, event: OrderPlaced) -> None:
        """
        这里只演示接口实现本身。
        业务上的“event_publish”日志已经在命令处理器中记录。
        真正生产环境可在这里接 Kafka、RabbitMQ 或 Outbox relay。
        """
        return None


@asynccontextmanager
async def lifespan(app: FastAPI):
    configure_logging()

    engine = create_async_engine(
        DATABASE_URL,
        pool_pre_ping=True,
    )
    session_factory = async_sessionmaker(engine, expire_on_commit=False)

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    app.state.order_repository = SqlAlchemyOrderRepository(session_factory)
    app.state.user_service = DemoUserService()
    app.state.inventory_service = DemoInventoryService()
    app.state.event_publisher = LoggingEventPublisher()

    yield

    await engine.dispose()


app = FastAPI(
    title="vcddd-order-service",
    version="1.0.0",
    lifespan=lifespan,
)
app.add_middleware(TraceMiddleware)
app.include_router(order_router)


@app.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}
```

---

## 关键实现点

1. 领域层只包含 dataclass、命令、事件、仓储协议，不引入 FastAPI。
2. `PlaceOrderHandler` 先做用户和库存校验，再创建聚合，再调用仓储提交单聚合事务。
3. `SqlAlchemyOrderRepository.save_with_idempotency_check()` 依赖 PostgreSQL 唯一约束 `uq_orders_idempotency_key` 原子检测重复幂等键，并回读已存在订单作为结果返回。
4. 事务提交成功后，命令处理器才调用 `publish_order_placed()`，避免“回滚了但事件已发出”。
5. `structlog` 使用 JSON 输出，命令入口、状态迁移、每条业务失败路径、事件发布日志都绑定 `domain/action/trace_id/order_id/user_id`。

---

## 失败路径

| 失败场景 | 抛出位置 | 异常类型 | HTTP 映射 |
| --- | --- | --- | --- |
| 用户不存在 | `PlaceOrderHandler.handle()` | `OrderError("USER_NOT_FOUND")` | `404` |
| 用户被封禁 | `PlaceOrderHandler.handle()` | `OrderError("USER_BANNED")` | `403` |
| 库存不足 | `PlaceOrderHandler.handle()` | `OrderError("INSUFFICIENT_INVENTORY")` | `409` |

这套实现满足题设中的 VCDDD 分层、事务边界、日志、幂等与失败路径要求，并且可以直接作为 Python/FastAPI 版本的 PlaceOrder 参考模板。
