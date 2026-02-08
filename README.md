<div align="center">

# OpenCoder Agent (OCA) 🍴

### A simplified, coding-focused fork of OpenAgents Control.

**Streamlined AI agents that learn YOUR coding patterns and ship production-ready code faster.**

🎯 **Pattern Control** • ✋ **Approval Gates** • 🔁 **Repeatable Results** • 📝 **Editable Agents**

**Multi-language:** TypeScript • Python • Go • Rust • Any language*  
**Model Agnostic:** Claude • GPT • Gemini • Opencode Zen •Local models

</div>

---

> **🍴 Forked from [OpenAgentsControl](https://github.com/darrenhinde/OpenAgentsControl)** - A simplified, focused fork optimized for streamlined coding workflows.

---

## About This Fork

This repository is a **fork of OpenAgentsControl** with a simplified architecture and additional focus on the coding experience:

### What's Different
- **📁 Agent-Specific Directories** - Each agent manages its own files (`openplanner/`, `openarchitect/`)
- **🧘 Streamlined Architecture** - Removed complexity while retaining core functionality
- **🎯 Coding-First Focus** - Prioritizes the developer experience during implementation
- **⚡ Simplified Workflows** - Reduced overhead for faster iteration cycles

### What We Kept
- ✅ Context-aware pattern learning
- ✅ Approval gates for quality control
- ✅ Editable agents via markdown
- ✅ Multi-language support
- ✅ Model agnostic design

📖 **For full documentation**, see the [original OpenAgentsControl repository](https://github.com/darrenhinde/OpenAgentsControl).

---

## 🚀 Quick Start

**Prerequisites:** [OpenCode CLI](https://opencode.ai/docs) • Bash 3.2+ • Git

### Step 1: Install

```bash
curl -fsSL https://raw.githubusercontent.com/sina96/OpenCoderAgent-slim/main/install.sh | bash -s standardCoder
```

### Step 2: Start Building

```bash
opencode --agent OpenAgent
> "Create a user authentication system"
```

### Step 3: Approve & Ship

The agent will propose a plan, you approve it, and it executes step-by-step with validation.

---

## 🎯 Which Agent Should I Use?

### OpenAgent (Start Here)

**Best for:** Learning the system, general tasks, quick implementations

```bash
opencode --agent OpenAgent
> "Create a user authentication system"
> "How do I implement authentication in Next.js?"
```

### OpenCoder (Production Development)

**Best for:** Complex features, multi-file refactoring, production systems

```bash
opencode --agent OpenCoder
> "Create a user authentication system"
> "Refactor this codebase to use dependency injection"
```

### OpenPlanner (Planning Specialist)

**Best for:** Creating implementation plans, architecture design, task breakdown

```bash
opencode --agent OpenPlanner
> "Plan the implementation of a payment processing system"
> "Break down this feature into manageable tasks"
```

**Features:**
- Creates detailed implementation plans
- Saves plans to `openplanner/plans/{task-slug}.md` (with approval)
- Or presents plans directly in conversation
- Breaks complex features into manageable steps

### OpenArchitect (Architecture Specialist)

**Best for:** System design, scalability planning, architectural decisions

```bash
opencode --agent OpenArchitect
> "Design the architecture for a real-time chat system"
> "Create an ADR for using microservices"
```

**Features:**
- Designs system architecture
- Creates Architecture Decision Records (ADRs)
- Saves designs to `openarchitect/architecture/{system-slug}.md` (with approval)
- Identifies scalability bottlenecks and trade-offs

### SystemBuilder (Custom AI Systems)

**Best for:** Building complete custom AI systems tailored to your domain

```bash
opencode --agent SystemBuilder
> "Create a customer support AI system"
```

---

## 🛠️ What's Included

### 🤖 Main Agents
- **OpenAgent** - General tasks, questions, learning (start here)
- **OpenCoder** - Production development, complex features
- **OpenPlanner** - **NEW** - Planning specialist with file creation support
- **OpenArchitect** - **NEW** - Architecture specialist with ADR support
- **SystemBuilder** - Generate custom AI systems

### 🔧 Specialized Subagents (Auto-delegated)
- **ContextScout** - Smart pattern discovery
- **TaskManager** - Breaks complex features into atomic subtasks
- **CoderAgent** - Focused code implementations
- **TestEngineer** - Test authoring and TDD
- **CodeReviewer** - Code review and security analysis
- **BuildAgent** - Type checking and build validation
- **ExternalScout** - Fetches live docs for external libraries

### ⚡ Productivity Commands
- `/add-context` - Interactive wizard to add your patterns
- `/commit` - Smart git commits with conventional format
- `/test` - Testing workflows
- `/optimize` - Code optimization
- `/context` - Context management

---

## 📚 More Information

For detailed documentation, examples, FAQ, and advanced features, see the [OpenAgentsControl repository](https://github.com/darrenhinde/OpenAgentsControl).

---

## License

This project is licensed under the MIT License.

---

**Made with ❤️ by developers, for developers.**

*This is a fork of [OpenAgentsControl](https://github.com/darrenhinde/OpenAgentsControl) with a simplified, coding-focused approach.*
