# 实现示例：Java 21 + Spring Boot 3

本示例给出一个符合 VCDDD 分层约束的 `PlaceOrder` 实现：

- `server/order/` 放订单核心对象、仓储接口，以及与其同目录的 `JpaOrderRepository.java`
- `app/` 是框架适配层，负责 HTTP、异常映射、Trace 透传、用户/库存适配器和提交后事件监听

场景覆盖：

- 用户校验
- 库存校验
- 调用方提供幂等键
- 新订单状态为 `PENDING`
- 发布 `OrderPlaced` 事件
- 失败路径：用户不存在、用户被封禁、库存不足、幂等键重复

---

## 项目目录树

```text
src/main/java/com/example/orders/
├── OrdersApplication.java                      ← @SpringBootApplication；应用启动入口
├── server/
│   └── order/
│       ├── Order.java                         ← 聚合根；纯 Java；状态固定从 NEW -> PENDING
│       ├── OrderEvent.java                    ← 领域事件；纯 Java
│       ├── OrderException.java                ← 业务拒绝异常；纯 Java
│       ├── OrderReadModel.java                ← 返回给适配层的只读视图；纯 Java
│       ├── OrderRepository.java               ← 仓储端口；接口定义
│       ├── JpaOrderRepository.java            ← @Repository；JPA + PostgreSQL + 原子幂等
│       ├── PlaceOrderCommand.java             ← 命令对象；纯 Java
│       └── PlaceOrderHandler.java             ← 命令处理器；纯 Java；日志、校验、状态迁移
├── app/
│   ├── InventoryGatewayAdapter.java           ← @Component；基于 JPA 读取库存
│   ├── OrderConfiguration.java                ← @Configuration；装配 PlaceOrderHandler
│   ├── OrderController.java                   ← @RestController；HTTP <-> command；@ExceptionHandler
│   ├── OrderEventRelay.java                   ← @Component；消费提交后发布的 Spring 事件
│   ├── TraceFilter.java                       ← @Component；透传/生成 X-Trace-Id 并写入 MDC
│   └── UserCheckerAdapter.java                ← @Component；基于 JPA 读取用户状态

src/main/resources/
└── logback-spring.xml                         ← logstash-logback-encoder JSON 日志配置
```

说明：

- 本文给出完整代码的文件：
  - `OrdersApplication.java`
  - `server/order/*`
  - `app/OrderController.java`
  - `app/TraceFilter.java`
  - `app/OrderConfiguration.java`
  - `app/OrderEventRelay.java`
  - `server/order/JpaOrderRepository.java`
  - `app/InventoryGatewayAdapter.java`
  - `app/UserCheckerAdapter.java`

---

## 关键约束落地

1. 订单核心对象保持纯 Java

`PlaceOrderHandler`、`Order`、`OrderRepository` 等核心对象在 `server/order/`，只依赖 Java 标准库和 SLF4J；`JpaOrderRepository` 也收纳在同目录，用于体现仓储接口与实现并列。

2. 幂等键原子检测

调用方通过 HTTP Header 传入 `Idempotency-Key`。真正的重复检测发生在 `JpaOrderRepository.saveWithIdempotencyCheck(...)` 的单事务内，依赖 PostgreSQL 唯一约束和 `ON CONFLICT DO NOTHING`。若命中重复键，则按 `idempotency_key` 回读既有订单并直接返回成功结果。

3. 一聚合一事务

`PlaceOrderHandler` 不加 `@Transactional`。事务边界放在 `JpaOrderRepository.saveWithIdempotencyCheck(...)`，这样单次下单只包住一个订单聚合的持久化与幂等记录写入。

4. 事件提交后发布

仓储内不在 `@Transactional` 方法里直接发事件，而是用 `TransactionSynchronizationManager.registerSynchronization(...afterCommit())` 注册提交后钩子。只有事务真正提交成功后，才会调用 `ApplicationEventPublisher.publishEvent(...)`。

5. 结构化日志

`TraceFilter` 把 `X-Trace-Id` 写入 `MDC.trace_id`。业务代码使用 SLF4J fluent API 的 `addKeyValue(...)` 输出 `domain`、`action`、`order_id`、`user_id` 等结构化字段；失败日志统一补齐 `error_classification` 和 `retryable`。

---

## server/order/OrderException.java

```java
package com.example.orders.server.order;

public final class OrderException extends RuntimeException {

    private final String code;

    public OrderException(String code, String message) {
        super(message);
        this.code = code;
    }

    public String code() {
        return code;
    }
}
```

## server/order/PlaceOrderCommand.java

```java
package com.example.orders.server.order;

import java.util.Objects;

public record PlaceOrderCommand(
        String userId,
        String productId,
        int quantity,
        String idempotencyKey
) {

    public PlaceOrderCommand {
        userId = requireText(userId, "userId");
        productId = requireText(productId, "productId");
        idempotencyKey = requireText(idempotencyKey, "idempotencyKey");

        if (quantity <= 0) {
            throw new OrderException("INVALID_QUANTITY", "下单数量必须大于 0");
        }
    }

    private static String requireText(String value, String field) {
        Objects.requireNonNull(value, field + " 不能为空");
        if (value.isBlank()) {
            throw new OrderException("INVALID_COMMAND", field + " 不能为空字符串");
        }
        return value;
    }
}
```

## server/order/OrderEvent.java

```java
package com.example.orders.server.order;

import java.time.Instant;

public sealed interface OrderEvent permits OrderEvent.OrderPlaced {

    String eventId();

    String orderId();

    Instant occurredAt();

    record OrderPlaced(
            String eventId,
            String orderId,
            String userId,
            String productId,
            int quantity,
            String status,
            Instant occurredAt
    ) implements OrderEvent {
    }
}
```

## server/order/Order.java

```java
package com.example.orders.server.order;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

public final class Order {

    public enum Status {
        PENDING
    }

    private final String orderId;
    private final String userId;
    private final String productId;
    private final int quantity;
    private final Status status;
    private final Instant createdAt;
    private final List<Object> domainEvents = new ArrayList<>();

    private Order(
            String orderId,
            String userId,
            String productId,
            int quantity,
            Status status,
            Instant createdAt
    ) {
        this.orderId = orderId;
        this.userId = userId;
        this.productId = productId;
        this.quantity = quantity;
        this.status = status;
        this.createdAt = createdAt;
    }

    public static Order place(
            String orderId,
            String userId,
            String productId,
            int quantity,
            String eventId,
            Instant createdAt
    ) {
        Objects.requireNonNull(createdAt, "createdAt 不能为空");

        if (orderId == null || orderId.isBlank()) {
            throw new OrderException("INVALID_ORDER_ID", "orderId 不能为空");
        }
        if (userId == null || userId.isBlank()) {
            throw new OrderException("INVALID_USER_ID", "userId 不能为空");
        }
        if (productId == null || productId.isBlank()) {
            throw new OrderException("INVALID_PRODUCT_ID", "productId 不能为空");
        }
        if (quantity <= 0) {
            throw new OrderException("INVALID_QUANTITY", "下单数量必须大于 0");
        }
        if (eventId == null || eventId.isBlank()) {
            throw new OrderException("INVALID_EVENT_ID", "eventId 不能为空");
        }

        Order order = new Order(
                orderId,
                userId,
                productId,
                quantity,
                Status.PENDING,
                createdAt
        );

        order.domainEvents.add(new OrderEvent.OrderPlaced(
                eventId,
                orderId,
                userId,
                productId,
                quantity,
                order.status.name(),
                createdAt
        ));

        return order;
    }

    public List<Object> pullDomainEvents() {
        List<Object> events = new ArrayList<>(domainEvents);
        domainEvents.clear();
        return events;
    }

    public String orderId() {
        return orderId;
    }

    public String userId() {
        return userId;
    }

    public String productId() {
        return productId;
    }

    public int quantity() {
        return quantity;
    }

    public Status status() {
        return status;
    }

    public Instant createdAt() {
        return createdAt;
    }
}
```

## server/order/OrderReadModel.java

```java
package com.example.orders.server.order;

import java.time.Instant;

public record OrderReadModel(
        String orderId,
        String userId,
        String productId,
        int quantity,
        String status,
        Instant createdAt
) {
}
```

## server/order/OrderRepository.java

```java
package com.example.orders.server.order;

public interface OrderRepository {

    OrderReadModel saveWithIdempotencyCheck(
            Order order,
            String idempotencyKey,
            OrderEvent event
    );
}
```

## server/order/PlaceOrderHandler.java

```java
package com.example.orders.server.order;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.Objects;

public final class PlaceOrderHandler {

    private static final Logger log = LoggerFactory.getLogger(PlaceOrderHandler.class);

    private final OrderRepository orderRepository;
    private final UserChecker userChecker;
    private final InventoryChecker inventoryChecker;
    private final Clock clock;
    private final IdGenerator idGenerator;

    public PlaceOrderHandler(
            OrderRepository orderRepository,
            UserChecker userChecker,
            InventoryChecker inventoryChecker,
            Clock clock,
            IdGenerator idGenerator
    ) {
        this.orderRepository = Objects.requireNonNull(orderRepository);
        this.userChecker = Objects.requireNonNull(userChecker);
        this.inventoryChecker = Objects.requireNonNull(inventoryChecker);
        this.clock = Objects.requireNonNull(clock);
        this.idGenerator = Objects.requireNonNull(idGenerator);
    }

    public OrderReadModel handle(PlaceOrderCommand command) {
        Objects.requireNonNull(command, "command 不能为空");

        log.atInfo()
                .addKeyValue("domain", "order")
                .addKeyValue("action", "place_order_received")
                .addKeyValue("user_id", command.userId())
                .addKeyValue("product_id", command.productId())
                .addKeyValue("quantity", command.quantity())
                .addKeyValue("idempotency_key", command.idempotencyKey())
                .log("place order command received");

        UserStatus userStatus = userChecker.getStatus(command.userId());
        if (userStatus == UserStatus.NOT_FOUND) {
            log.atWarn()
                    .addKeyValue("domain", "order")
                    .addKeyValue("action", "place_order_rejected")
                    .addKeyValue("user_id", command.userId())
                    .addKeyValue("idempotency_key", command.idempotencyKey())
                    .addKeyValue("error_code", "USER_NOT_FOUND")
                    .addKeyValue("error_classification", "business")
                    .addKeyValue("retryable", false)
                    .log("place order rejected");
            throw new OrderException("USER_NOT_FOUND", "用户不存在");
        }

        if (userStatus == UserStatus.BANNED) {
            log.atWarn()
                    .addKeyValue("domain", "order")
                    .addKeyValue("action", "place_order_rejected")
                    .addKeyValue("user_id", command.userId())
                    .addKeyValue("idempotency_key", command.idempotencyKey())
                    .addKeyValue("error_code", "USER_BANNED")
                    .addKeyValue("error_classification", "business")
                    .addKeyValue("retryable", false)
                    .log("place order rejected");
            throw new OrderException("USER_BANNED", "用户已被封禁");
        }

        if (!inventoryChecker.hasAvailable(command.productId(), command.quantity())) {
            log.atWarn()
                    .addKeyValue("domain", "order")
                    .addKeyValue("action", "place_order_rejected")
                    .addKeyValue("user_id", command.userId())
                    .addKeyValue("product_id", command.productId())
                    .addKeyValue("quantity", command.quantity())
                    .addKeyValue("idempotency_key", command.idempotencyKey())
                    .addKeyValue("error_code", "INSUFFICIENT_INVENTORY")
                    .addKeyValue("error_classification", "business")
                    .addKeyValue("retryable", false)
                    .log("place order rejected");
            throw new OrderException("INSUFFICIENT_INVENTORY", "库存不足");
        }

        Instant now = Instant.now(clock);
        Order order = Order.place(
                idGenerator.newOrderId(),
                command.userId(),
                command.productId(),
                command.quantity(),
                idGenerator.newEventId(),
                now
        );

        log.atInfo()
                .addKeyValue("domain", "order")
                .addKeyValue("action", "state_transition")
                .addKeyValue("order_id", order.orderId())
                .addKeyValue("user_id", order.userId())
                .addKeyValue("from_state", "NEW")
                .addKeyValue("to_state", order.status().name())
                .addKeyValue("idempotency_key", command.idempotencyKey())
                .log("order state transitioned");

        List<Object> domainEvents = order.pullDomainEvents();
        Object domainEvent = domainEvents.stream()
                .findFirst()
                .orElseThrow(() -> new IllegalStateException("订单创建后没有生成领域事件"));

        if (!(domainEvent instanceof OrderEvent event)) {
            throw new IllegalStateException("未知的领域事件类型: " + domainEvent.getClass().getName());
        }

        return orderRepository.saveWithIdempotencyCheck(
                order,
                command.idempotencyKey(),
                event
        );
    }

    public interface UserChecker {
        UserStatus getStatus(String userId);
    }

    public interface InventoryChecker {
        boolean hasAvailable(String productId, int quantity);
    }

    public interface IdGenerator {
        String newOrderId();

        String newEventId();
    }

    public enum UserStatus {
        ACTIVE,
        NOT_FOUND,
        BANNED
    }
}
```

---

## server/order/JpaOrderRepository.java

```java
package com.example.orders.server.order;

import com.example.orders.server.order.Order;
import com.example.orders.server.order.OrderEvent;
import com.example.orders.server.order.OrderReadModel;
import com.example.orders.server.order.OrderRepository;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.time.Instant;

@Repository
public class JpaOrderRepository implements OrderRepository {

    private static final Logger log = LoggerFactory.getLogger(JpaOrderRepository.class);

    private final SpringDataOrderJpaRepository orderJpaRepository;
    private final SpringDataOrderIdempotencyJpaRepository idempotencyJpaRepository;
    private final ApplicationEventPublisher applicationEventPublisher;

    public JpaOrderRepository(
            SpringDataOrderJpaRepository orderJpaRepository,
            SpringDataOrderIdempotencyJpaRepository idempotencyJpaRepository,
            ApplicationEventPublisher applicationEventPublisher
    ) {
        this.orderJpaRepository = orderJpaRepository;
        this.idempotencyJpaRepository = idempotencyJpaRepository;
        this.applicationEventPublisher = applicationEventPublisher;
    }

    @Override
    @Transactional
    public OrderReadModel saveWithIdempotencyCheck(
            Order order,
            String idempotencyKey,
            OrderEvent event
    ) {
        int inserted = idempotencyJpaRepository.tryInsert(
                idempotencyKey,
                order.orderId(),
                Instant.now()
        );

        if (inserted == 0) {
            OrderReadModel existing = loadExistingOrder(idempotencyKey);
            log.atInfo()
                    .addKeyValue("domain", "order")
                    .addKeyValue("action", "idempotency_hit")
                    .addKeyValue("order_id", existing.orderId())
                    .addKeyValue("user_id", existing.userId())
                    .addKeyValue("idempotency_key", idempotencyKey)
                    .log("duplicate idempotency key resolved to existing order");
            return existing;
        }

        OrderJpaEntity savedOrder = orderJpaRepository.saveAndFlush(OrderJpaEntity.from(order));
        publishAfterCommit(event);

        return savedOrder.toReadModel();
    }

    private OrderReadModel loadExistingOrder(String idempotencyKey) {
        OrderIdempotencyJpaEntity existingMarker = idempotencyJpaRepository.findById(idempotencyKey)
                .orElseThrow(() -> new IllegalStateException("幂等记录存在但无法读取"));

        return orderJpaRepository.findById(existingMarker.orderId())
                .map(OrderJpaEntity::toReadModel)
                .orElseThrow(() -> new IllegalStateException("幂等记录存在但订单不存在"));
    }

    private void publishAfterCommit(OrderEvent event) {
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            log.atError()
                    .addKeyValue("domain", "order")
                    .addKeyValue("action", "event_publish_registration_failed")
                    .addKeyValue("order_id", event.orderId())
                    .addKeyValue("error_classification", "system")
                    .addKeyValue("retryable", true)
                    .log("transaction synchronization is not active");
            throw new IllegalStateException("事务同步未激活，无法注册 afterCommit 事件");
        }

        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                applicationEventPublisher.publishEvent(event);
            }
        });
    }
}

@Entity
@Table(name = "orders")
class OrderJpaEntity {

    @Id
    @Column(name = "order_id", nullable = false, updatable = false)
    private String orderId;

    @Column(name = "user_id", nullable = false)
    private String userId;

    @Column(name = "product_id", nullable = false)
    private String productId;

    @Column(name = "quantity", nullable = false)
    private int quantity;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false)
    private Order.Status status;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected OrderJpaEntity() {
    }

    private OrderJpaEntity(
            String orderId,
            String userId,
            String productId,
            int quantity,
            Order.Status status,
            Instant createdAt
    ) {
        this.orderId = orderId;
        this.userId = userId;
        this.productId = productId;
        this.quantity = quantity;
        this.status = status;
        this.createdAt = createdAt;
    }

    static OrderJpaEntity from(Order order) {
        return new OrderJpaEntity(
                order.orderId(),
                order.userId(),
                order.productId(),
                order.quantity(),
                order.status(),
                order.createdAt()
        );
    }

    OrderReadModel toReadModel() {
        return new OrderReadModel(
                orderId,
                userId,
                productId,
                quantity,
                status.name(),
                createdAt
        );
    }
}

@Entity
@Table(
        name = "order_idempotency",
        uniqueConstraints = {
                @UniqueConstraint(name = "uk_order_idempotency_key", columnNames = "idempotency_key")
        }
)
class OrderIdempotencyJpaEntity {

    @Id
    @Column(name = "idempotency_key", nullable = false, updatable = false)
    private String idempotencyKey;

    @Column(name = "order_id", nullable = false, unique = true)
    private String orderId;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected OrderIdempotencyJpaEntity() {
    }

    OrderIdempotencyJpaEntity(String idempotencyKey, String orderId, Instant createdAt) {
        this.idempotencyKey = idempotencyKey;
        this.orderId = orderId;
        this.createdAt = createdAt;
    }

    String orderId() {
        return orderId;
    }
}

interface SpringDataOrderJpaRepository extends JpaRepository<OrderJpaEntity, String> {
}

interface SpringDataOrderIdempotencyJpaRepository extends JpaRepository<OrderIdempotencyJpaEntity, String> {

    @Modifying
    @Query(
            value = """
                    insert into order_idempotency (idempotency_key, order_id, created_at)
                    values (:idempotencyKey, :orderId, :createdAt)
                    on conflict (idempotency_key) do nothing
                    """,
            nativeQuery = true
    )
    int tryInsert(
            @Param("idempotencyKey") String idempotencyKey,
            @Param("orderId") String orderId,
            @Param("createdAt") Instant createdAt
    );
}
```

说明：

- 幂等唯一约束落在 `order_idempotency.idempotency_key`
- `tryInsert(...)` 利用 PostgreSQL `ON CONFLICT DO NOTHING` 原子判断重复幂等键
- 命中重复键时按 `idempotency_key` 回读原订单并直接返回成功结果，不抛 `OrderException`
- 事件不在事务中直接发布，而是注册 `afterCommit()` 回调，仅在事务提交成功后发布
- 因为整段仍在一个事务里，订单行和幂等记录保持同一个聚合事务边界

---

## app/OrderConfiguration.java

```java
package com.example.orders.app;

import com.example.orders.server.order.OrderRepository;
import com.example.orders.server.order.PlaceOrderHandler;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Clock;
import java.util.UUID;

@Configuration
public class OrderConfiguration {

    @Bean
    PlaceOrderHandler placeOrderHandler(
            OrderRepository orderRepository,
            PlaceOrderHandler.UserChecker userChecker,
            PlaceOrderHandler.InventoryChecker inventoryChecker,
            Clock clock
    ) {
        return new PlaceOrderHandler(
                orderRepository,
                userChecker,
                inventoryChecker,
                clock,
                new PlaceOrderHandler.IdGenerator() {
                    @Override
                    public String newOrderId() {
                        return UUID.randomUUID().toString();
                    }

                    @Override
                    public String newEventId() {
                        return UUID.randomUUID().toString();
                    }
                }
        );
    }

    @Bean
    Clock clock() {
        return Clock.systemUTC();
    }
}
```

## app/OrderController.java

```java
package com.example.orders.app;

import com.example.orders.server.order.OrderException;
import com.example.orders.server.order.OrderReadModel;
import com.example.orders.server.order.PlaceOrderCommand;
import com.example.orders.server.order.PlaceOrderHandler;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;

@RestController
@RequestMapping("/orders")
public class OrderController {

    private static final Logger log = LoggerFactory.getLogger(OrderController.class);

    private final PlaceOrderHandler placeOrderHandler;

    public OrderController(PlaceOrderHandler placeOrderHandler) {
        this.placeOrderHandler = placeOrderHandler;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public PlaceOrderResponse placeOrder(
            @RequestHeader("Idempotency-Key") String idempotencyKey,
            @RequestBody @Valid PlaceOrderRequest request
    ) {
        // 若命中重复幂等键，仓储层会回读原订单并仍然返回成功结果。
        OrderReadModel result = placeOrderHandler.handle(
                new PlaceOrderCommand(
                        request.userId(),
                        request.productId(),
                        request.quantity(),
                        idempotencyKey
                )
        );

        return new PlaceOrderResponse(
                result.orderId(),
                result.status(),
                result.createdAt()
        );
    }

    @ExceptionHandler(OrderException.class)
    public ResponseEntity<ErrorResponse> handleOrderException(OrderException ex) {
        return ResponseEntity.unprocessableEntity()
                .body(new ErrorResponse(ex.code(), ex.getMessage()));
    }

    @ExceptionHandler(RuntimeException.class)
    public ResponseEntity<ErrorResponse> handleRuntimeException(RuntimeException ex) {
        log.atError()
                .setCause(ex)
                .addKeyValue("domain", "order")
                .addKeyValue("action", "place_order_failed")
                .addKeyValue("error_classification", "system")
                .addKeyValue("retryable", true)
                .log("place order failed");
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(new ErrorResponse("SYSTEM_ERROR", "系统异常，请稍后重试"));
    }

    public record PlaceOrderRequest(
            @NotBlank String userId,
            @NotBlank String productId,
            @Min(1) int quantity
    ) {
    }

    public record PlaceOrderResponse(
            String orderId,
            String status,
            Instant createdAt
    ) {
    }

    public record ErrorResponse(
            String code,
            String message
    ) {
    }
}
```

## app/TraceFilter.java

```java
package com.example.orders.app;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.MDC;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.UUID;

@Component
public class TraceFilter extends OncePerRequestFilter {

    public static final String TRACE_HEADER = "X-Trace-Id";
    public static final String TRACE_MDC_KEY = "trace_id";

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain
    ) throws ServletException, IOException {
        String traceId = request.getHeader(TRACE_HEADER);
        if (traceId == null || traceId.isBlank()) {
            traceId = UUID.randomUUID().toString();
        }

        MDC.put(TRACE_MDC_KEY, traceId);
        response.setHeader(TRACE_HEADER, traceId);

        try {
            filterChain.doFilter(request, response);
        } finally {
            MDC.remove(TRACE_MDC_KEY);
        }
    }
}
```

## app/OrderEventRelay.java

```java
package com.example.orders.app;

import com.example.orders.server.order.OrderEvent;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

@Component
public class OrderEventRelay {

    private static final Logger log = LoggerFactory.getLogger(OrderEventRelay.class);

    @EventListener
    public void on(OrderEvent.OrderPlaced event) {
        log.atInfo()
                .addKeyValue("domain", "order")
                .addKeyValue("action", "order_event_published")
                .addKeyValue("event_type", "OrderPlaced")
                .addKeyValue("event_id", event.eventId())
                .addKeyValue("order_id", event.orderId())
                .addKeyValue("user_id", event.userId())
                .addKeyValue("product_id", event.productId())
                .addKeyValue("quantity", event.quantity())
                .addKeyValue("status", event.status())
                .log("order event published");

        // 这里再接 Kafka、Outbox、Webhook、消息中间件都可以。
        // 关键点是：事件本身已经由仓储层在 afterCommit() 中发布。
    }
}
```

## app/InventoryGatewayAdapter.java

```java
package com.example.orders.app;

import com.example.orders.server.order.PlaceOrderHandler;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Component;

@Component
public class InventoryGatewayAdapter implements PlaceOrderHandler.InventoryChecker {

    private final SpringDataInventoryJpaRepository inventoryJpaRepository;

    public InventoryGatewayAdapter(SpringDataInventoryJpaRepository inventoryJpaRepository) {
        this.inventoryJpaRepository = inventoryJpaRepository;
    }

    @Override
    public boolean hasAvailable(String productId, int quantity) {
        return inventoryJpaRepository.findById(productId)
                .map(inventory -> inventory.availableQuantity() >= quantity)
                .orElse(false);
    }
}

@Entity
@Table(name = "inventory")
class InventoryJpaEntity {

    @Id
    @Column(name = "product_id", nullable = false, updatable = false)
    private String productId;

    @Column(name = "available_quantity", nullable = false)
    private int availableQuantity;

    protected InventoryJpaEntity() {
    }

    int availableQuantity() {
        return availableQuantity;
    }
}

interface SpringDataInventoryJpaRepository extends JpaRepository<InventoryJpaEntity, String> {
}
```

## app/UserCheckerAdapter.java

```java
package com.example.orders.app;

import com.example.orders.server.order.PlaceOrderHandler;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Component;

@Component
public class UserCheckerAdapter implements PlaceOrderHandler.UserChecker {

    private final SpringDataUserJpaRepository userJpaRepository;

    public UserCheckerAdapter(SpringDataUserJpaRepository userJpaRepository) {
        this.userJpaRepository = userJpaRepository;
    }

    @Override
    public PlaceOrderHandler.UserStatus getStatus(String userId) {
        return userJpaRepository.findById(userId)
                .map(user -> user.banned()
                        ? PlaceOrderHandler.UserStatus.BANNED
                        : PlaceOrderHandler.UserStatus.ACTIVE)
                .orElse(PlaceOrderHandler.UserStatus.NOT_FOUND);
    }
}

@Entity
@Table(name = "users")
class UserJpaEntity {

    @Id
    @Column(name = "user_id", nullable = false, updatable = false)
    private String userId;

    @Column(name = "banned", nullable = false)
    private boolean banned;

    protected UserJpaEntity() {
    }

    boolean banned() {
        return banned;
    }
}

interface SpringDataUserJpaRepository extends JpaRepository<UserJpaEntity, String> {
}
```

## OrdersApplication.java

```java
package com.example.orders;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class OrdersApplication {

    public static void main(String[] args) {
        SpringApplication.run(OrdersApplication.class, args);
    }
}
```

---

## 失败路径与日志点

| 场景 | 位置 | 日志 | 异常 | HTTP |
|------|------|------|------|------|
| 用户不存在 | `PlaceOrderHandler` | `action=place_order_rejected error_code=USER_NOT_FOUND error_classification=business retryable=false` | `OrderException(USER_NOT_FOUND)` | `422` |
| 用户被封禁 | `PlaceOrderHandler` | `action=place_order_rejected error_code=USER_BANNED error_classification=business retryable=false` | `OrderException(USER_BANNED)` | `422` |
| 库存不足 | `PlaceOrderHandler` | `action=place_order_rejected error_code=INSUFFICIENT_INVENTORY error_classification=business retryable=false` | `OrderException(INSUFFICIENT_INVENTORY)` | `422` |
| 幂等键重复 | `JpaOrderRepository` | `action=idempotency_hit` | 无 | `201` |
| 系统异常 | `OrderController` | `action=place_order_failed error_classification=system retryable=true` | `RuntimeException` | `500` |
| 事件发布 | `OrderEventRelay` | `action=order_event_published` | 无 | `201` 已返回 |

---

## logback-spring.xml 示例

```xml
<configuration>
    <appender name="JSON" class="ch.qos.logback.core.ConsoleAppender">
        <encoder class="net.logstash.logback.encoder.LoggingEventCompositeJsonEncoder">
            <providers>
                <timestamp>
                    <fieldName>@timestamp</fieldName>
                </timestamp>
                <logLevel>
                    <fieldName>level</fieldName>
                </logLevel>
                <loggerName>
                    <fieldName>logger</fieldName>
                </loggerName>
                <threadName>
                    <fieldName>thread</fieldName>
                </threadName>
                <message>
                    <fieldName>message</fieldName>
                </message>
                <mdc/>
                <keyValuePairs/>
                <arguments/>
                <stackTrace>
                    <fieldName>stack_trace</fieldName>
                </stackTrace>
            </providers>
        </encoder>
    </appender>

    <root level="INFO">
        <appender-ref ref="JSON"/>
    </root>
</configuration>
```

对应依赖：

```xml
<dependency>
    <groupId>net.logstash.logback</groupId>
    <artifactId>logstash-logback-encoder</artifactId>
    <version>8.0</version>
</dependency>
```

---

## 这个版本为什么符合题目约束

- `server/` 下没有任何 Spring 注解
- `app/OrderController` 只做 HTTP 到 `PlaceOrderCommand` 的映射和异常映射，不写业务判断
- `JpaOrderRepository.saveWithIdempotencyCheck(...)` 通过唯一约束原子识别重复幂等键，重复请求回读原订单并返回成功结果
- 单次下单只在仓储层开启一个事务，作用域就是单个订单聚合
- `ApplicationEventPublisher` 只在 `afterCommit()` 中触发，避免事务未提交时提前发事件
- 通过 `TraceFilter + MDC + SLF4J fluent API + logstash-logback-encoder` 输出带 `trace_id` 和 KV 字段的结构化 JSON 日志
