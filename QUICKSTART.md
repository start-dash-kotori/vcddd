# VCDDD Quick Start

> No DDD knowledge required. Follow these steps to ship a well-designed product in five stages.

---

## Step 1: Install the Skill

### Option A: cc-switch (recommended)

In the cc-switch Skills panel, add a repository:

- **Owner**: `StCornelia`
- **Repo**: `vcddd`
- **Branch**: `main`
- **Subdirectory**: leave empty

Once installed, the skill syncs automatically to your AI agent (Claude Code, Codex, etc.).

### Option B: Manual install (Claude Code)

```bash
git clone https://github.com/StCornelia/vcddd.git ~/.claude/skills/vcddd
```

### Option C: Manual install (Codex CLI)

```bash
git clone https://github.com/StCornelia/vcddd.git ~/.codex/skills/vcddd
```

---

## Step 2: Load the Skill

After installation, tell the AI to load the skill at the start of a session:

```
Load the vcddd skill. I want to design a new product.
```

Or just describe your project — the AI will identify and activate the skill:

```
I want to build a vacation rental management tool. Use VCDDD to help me design it.
```

---

## Step 3: Follow the Five Steps

VCDDD has five stages. You don't need to understand all the theory — just answer the AI's questions honestly and confirm the output at the end of each stage.

---

### V — Describe What You Want to Build

**Your job**: Say what you want to build in your own words. No need to be formal.

**Example**:

```
I want to build a management tool for short-term rental hosts.
Right now hosts manage reservations through WeChat groups and Excel, which is chaos.
I want a single place to see all rooms, bookings, guests, and payments.
```

**What the AI does**: Structures your description into `input.md` for your review.

**Your confirmation**:

```
That description is accurate. Confirmed.
```

---

### C — Clarify the Facts Together

**Your job**: Answer the AI's clarifying questions. These questions turn vague ideas into confirmed, written business facts.

**The AI might ask**:

- How many rooms does a typical host manage?
- Where do reservations come from? (direct messages, or OTA platforms?)
- Is payment online or offline? How are refunds handled?
- If two bookings conflict for the same room, who is responsible for catching that?

**Just answer honestly.** If you don't know something, say so — the AI marks it as "to be confirmed."

**At the end**: The AI produces a `facts.md` with all confirmed facts. Review it:

```
Fact #3 is wrong — payment isn't monthly, it's per-booking on completion.
Everything else is accurate. Confirmed.
```

**This stage is complete when**: You have confirmed every item in `facts.md`.

---

### D¹ — AI Designs the System Boundaries (You Approve)

**Your job**: Mostly review what the AI produces. It will split the system into "domains" (functional areas) and explain what each domain is and isn't responsible for.

You don't need to know DDD. Just use common sense to evaluate whether the design makes sense.

**Example of what the AI might show you**:

```
I've identified the following domains:
1. Room Domain — manages room info and availability
2. Booking Domain — manages creation, changes, and cancellations
3. Payment Domain — manages receipts and refunds
4. Guest Domain — manages guest information

Question: Who should be responsible for conflict detection
(checking if a room is already booked)? The Booking Domain or the Room Domain?
```

**You answer**:

```
Booking Domain — conflicts are caused by bookings, so bookings should catch them.
```

The AI continues designing until each domain has a clear specification document.

**At the end**:

```
The domain design looks reasonable. Confirmed — ready for the next step.
```

---

### D² — Lock In the Tech Stack

**Your job**: Tell the AI what technology you want to use.

**Example**:

```
Flutter for the mobile app, Go for the backend, PostgreSQL for the database,
deployed on AWS.
```

If you're unsure:

```
I want a web frontend. Help me choose a backend stack that gets to production quickly.
```

The AI writes a `tech-stack.md` document that governs all future code. Review and confirm:

```
Tech stack confirmed. Ready to start writing code.
```

---

### D³ — Write the Code

**Your job**: Direct the AI to implement specific parts of the system.

Unlike asking an AI to "just write code," every decision now has a design document behind it. The AI writes code that matches the domain design and facts you confirmed — not code it invented on the spot.

**Example**:

```
Implement the core logic for the Booking Domain: creating a booking and detecting conflicts.
```

If the AI finds a gap in the design documents, it will stop and tell you:

```
I noticed that facts.md doesn't define what happens when a booking times out
without payment. I need to clarify this before implementing the payment flow.
```

Go back, add the missing fact, confirm it, then continue.

---

## FAQ

**Q: I don't know DDD. Can I still use this?**

Yes. That's one of the design goals. You handle the business thinking; the AI handles the technical design.

**Q: Do I have to do all five steps?**

Yes, and in order. Skipping "clarify facts" means your design is built on assumptions. Skipping "domain design" means your code has no business structure and will become tangled quickly.

**Q: I already have a running project. Can I use this?**

Yes, but start from V — reconstruct the business facts about your existing system into a `facts.md`, then review whether the existing code actually aligns with them. It's one extra "map what exists" step compared to a new project.

**Q: The domain design is confusing. What do I do?**

Ask directly:

```
I don't understand this domain design. Can you explain it in plain business terms?
Especially the "collaboration contract" part.
```

You have the right to ask the AI to explain every design decision in non-technical language until you can evaluate and approve it.

**Q: How long should each step take?**

No time limit. V might take 10 minutes; C might take several rounds of conversation for a complex product. What matters is that you genuinely confirm each document at the end of the step — not just click through it.

---

## Minimal Full Example

```
User: Load vcddd. I want to build an internal leave-approval tool.
      Employees submit requests, managers approve, HR sees reports.

AI:   [Entering V] Let me structure your intent...
      [Generates input.md]
      Please confirm whether this description is accurate.

User: Accurate. Confirmed.

AI:   [Entering C] A few clarifying questions:
      1. Can an employee have multiple open leave requests at the same time?
      2. Can an employee resubmit after a rejection?
      3. Do different leave types (annual, sick, personal) need different rules?

User: 1. Yes, but not overlapping time periods.
      2. Yes, but only once.
      3. Yes — annual leave has a balance limit; sick and personal do not.

AI:   [Produces facts.md with 11 items]
      Please confirm each item...

User: Item 7 is wrong — sick leave doesn't need pre-approval, it can be logged retroactively.

AI:   [Updates facts.md] Updated. Please re-confirm.

User: Confirmed.

AI:   [Entering D¹] Based on the confirmed facts, I've identified 3 domains:
      Request Domain, Approval Domain, Balance Domain...
      [Generates domain design documents]

User: [After review] Confirmed. Move to tech stack.

AI:   [Entering D²] What tech stack are you using?

User: React + Node.js + PostgreSQL.

AI:   [Generates tech-stack.md, confirmed, enters D³]

User: Start with the Request Domain — full flow for submitting a leave request.

AI:   [Writes code — all naming and logic strictly follows facts.md and domain design]
```

---

## Starter Prompt

Paste this to begin a VCDDD session:

```
Please load the vcddd skill.

I want to design a new project using the VCDDD method. Please guide me starting from the V step.
I'm not familiar with DDD — please explain each step in business terms, not technical jargon.

Here's my project idea:
[Write your idea here — as rough and informal as you like]
```
