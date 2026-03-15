# Osmedeus AI Scanner — Usage Guide

The AI scanner replaces static workflow pipelines with an LLM-powered **brain agent** that reasons about targets, selects tools, and adapts its strategy based on findings — like a senior pentester running the engagement.

---

## Quick Start

```bash
# 1. Set your OpenAI API key
export OPENAI_API_KEY=sk-xxx

# 2a. Docker (recommended) — includes all security tools pre-installed
OPENAI_API_KEY=$OPENAI_API_KEY \
  docker compose -f build/docker/docker-compose.ai.yaml up -d

# 2b. Or run locally (requires tools installed via `osmedeus install binary --all`)
cp public/presets/ai-scan-settings.yaml ~/osmedeus-base/osm-settings.yaml
osmedeus run -f ai-scan -t target.com

# 3. Run a scan inside Docker
docker compose -f build/docker/docker-compose.ai.yaml exec osmedeus \
  osmedeus run -f ai-scan -t target.com

# 4. View logs
docker compose -f build/docker/docker-compose.ai.yaml logs -f osmedeus

# 5. Tear down
docker compose -f build/docker/docker-compose.ai.yaml down
```

---

## Available Workflows

| Workflow | Description | Typical Duration |
|----------|-------------|-----------------|
| `ai-scan` | Full autonomous scan — recon, enumeration, vuln discovery, reporting. Bug bounty profile by default. | 30–90 min |
| `ai-recon` | Reconnaissance only — passive and semi-passive asset discovery. No active exploitation or fuzzing. | 15–30 min |
| `ai-vuln` | Vulnerability assessment — runs recon first, then focused vulnerability hunting with nuclei, fuzzing, and manual checks. | 45–120 min |
| `ai-redteam` | Red team simulation — stealthy, objective-oriented, attack-chain focused. Lower scan rates, careful OPSEC. | 60–180 min |

### Run Examples

```bash
# Full AI scan against a domain
osmedeus run -f ai-scan -t example.com

# Recon only — no active testing
osmedeus run -f ai-recon -t example.com

# Vulnerability assessment with 2-hour timeout
osmedeus run -f ai-vuln -t example.com --timeout 2h

# Red team simulation
osmedeus run -f ai-redteam -t example.com

# Scan multiple targets concurrently (5 at a time)
osmedeus run -f ai-scan -T targets.txt -c 5

# Run specific modules in sequence
osmedeus run -m recon/subdomain-enum -m vuln/nuclei-scan -t example.com
```

---

## Profiles

Profiles modify the brain agent's behavior by injecting additional constraints and priorities. They live in `prompts/profiles/`.

| Profile | File | Behavior |
|---------|------|----------|
| **bug-bounty** | `prompts/profiles/bug-bounty.txt` | Safe, scoped, impact-first. Strict scope enforcement, P1–P4 severity classification, report-quality focus. Avoids destructive testing and out-of-scope assets. |
| **red-team** | `prompts/profiles/red-team.txt` | Stealthy, persistent, exploitation-focused. Minimizes network noise, uses objective-oriented attack chains, emulates real threat actor TTPs. Prefers "living off the land" techniques. |
| **recon-only** | `prompts/profiles/recon-only.txt` | No active testing, mapping only. Passive/semi-passive reconnaissance producing an attack surface map with risk annotations. Explicitly forbids fuzzing, injection, and vulnerability scanning. |

Profiles are loaded as additional context alongside the brain system prompt. Profile constraints **override** default brain behavior.

---

## Customizing Prompts

### Where Prompts Live

```
prompts/
├── brain/
│   ├── hacker-brain.txt          # Core brain system prompt (OsmBrain identity)
│   └── attack-planning.txt       # Plan-stage prompt (pre-execution planning)
├── profiles/
│   ├── bug-bounty.txt            # Bug bounty constraints
│   ├── red-team.txt              # Red team constraints
│   └── recon-only.txt            # Recon-only constraints
├── agents/
│   ├── recon-specialist.txt      # Sub-agent: reconnaissance
│   ├── vuln-specialist.txt       # Sub-agent: vulnerability hunting
│   ├── web-specialist.txt        # Sub-agent: web application testing
│   ├── network-specialist.txt    # Sub-agent: network assessment
│   └── report-specialist.txt     # Sub-agent: report generation
└── reasoning/
    ├── tool-selection.txt        # Reasoning template: choosing tools
    ├── attack-chain.txt          # Reasoning template: chaining findings
    └── finding-analysis.txt      # Reasoning template: analyzing results
```

### How to Modify Brain Behavior

1. **Edit the brain prompt** — `prompts/brain/hacker-brain.txt` defines OsmBrain's identity, reasoning framework (the "Five Questions"), and phase management. Add domain-specific knowledge or constraints here.

2. **Edit a profile** — Profiles in `prompts/profiles/` are injected alongside the brain prompt. Modify priorities, forbidden actions, or time allocation.

3. **Edit reasoning templates** — Templates in `prompts/reasoning/` are injected when the brain needs structured decision-making (tool selection, attack chain analysis, finding evaluation).

4. **Edit sub-agent prompts** — Prompts in `prompts/agents/` define specialist sub-agents. The brain delegates focused tasks (recon, vuln scanning, reporting) to these sub-agents.

### Adding New Reasoning Templates

Create a new `.txt` file in `prompts/reasoning/`:

```text
################################################################################
#            OSMEDEUS CUSTOM REASONING — MY TEMPLATE
#
#  Purpose : Description of when this template is used
#  Version : 1.0.0
################################################################################

# Step-by-step reasoning instructions here...
# Use structured formats (tables, checklists) for consistency.
```

Reference it in your workflow YAML via the `system_prompt` or `plan_prompt` fields of an agent step.

### Creating Custom Profiles

Create a new `.txt` file in `prompts/profiles/`:

```text
################################################################################
#           OSMEDEUS PROFILE: MY CUSTOM PROFILE
#
#  Purpose : When and why this profile is used
#  Version : 1.0.0
################################################################################

This profile is active.  All actions MUST comply with these constraints.
These rules OVERRIDE any default behavior from the brain system prompt.

# 1. CONSTRAINTS
# ...your rules here...

# 2. PRIORITIES
# ...your priorities here...

# 3. TIME ALLOCATION
# ...your time budget here...
```

---

## Adding New Modules

Modules live in `workflows/modules/` organized by category (`recon/`, `vuln/`, `network/`, `report/`). Each module is a YAML file.

### YAML Format Reference

```yaml
name: my-custom-scan
kind: module
desc: One-line description of what this module does
tags: category, tool-name, technique

params:
  - name: threads
    value: "10"
  - name: wordlist
    value: "{{Data}}/my-wordlist.txt"

steps:
  - name: setup
    type: bash
    commands:
      - mkdir -p {{Output}}/my-scan

  - name: run-tool
    type: bash
    command: >
      {{Binaries}}/mytool -t {{Target}}
      --threads {{threads}}
      -o {{Output}}/my-scan/results.json
    timeout: 600
    on_error: continue

  - name: process-results
    type: function
    function: db_import_sarif("{{Workspace}}", "{{Output}}/my-scan/results.sarif")
    exports:
      findings_count: "{{function_output}}"
```

### How to Add a New Tool

1. **Create a module YAML** in the appropriate `workflows/modules/<category>/` directory.
2. **Install the tool binary** — add it to `osmedeus install binary` registry or place it in `{{base_folder}}/external-binaries/`.
3. **Reference the binary** as `{{Binaries}}/toolname` in your step commands.
4. **Test the module** standalone: `osmedeus run -m <category>/<module-name> -t target.com`

### How the Brain Discovers and Uses Modules

The brain agent has access to `run_module` and `run_flow` preset tools. When the brain decides a particular technique is needed (e.g., subdomain enumeration), it calls `run_module` with the module name. The executor loads the corresponding YAML, resolves templates, and runs each step.

Available module categories:
- `recon/` — subdomain-enum, dns-enum, http-probe, port-scan
- `vuln/` — nuclei-scan, sqli-scan, ssl-audit, web-fuzz
- `network/` — service-enum, smb-audit
- `report/` — generate-report

---

## Architecture Overview

### How the Brain Works

```
┌───────────────────────────────────────────────────────────────────┐
│                         CLI / API                                 │
│              osmedeus run -f ai-scan -t target.com                │
└───────────────────────┬───────────────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────────────┐
│                     Executor Engine                               │
│  Loads workflow YAML → initializes context → dispatches steps     │
└───────────────────────┬───────────────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────────────┐
│                    Brain Agent Step                                │
│  type: agent                                                      │
│  system_prompt: prompts/brain/hacker-brain.txt                    │
│  plan_prompt:   prompts/brain/attack-planning.txt                 │
│  profile:       prompts/profiles/bug-bounty.txt (or red-team, …) │
│  max_iterations: N                                                │
└───────────────────────┬───────────────────────────────────────────┘
                        │
              ┌─────────┴──────────┐
              ▼                    ▼
   ┌──────────────────┐  ┌──────────────────┐
   │  Tool Calling     │  │  Sub-Agent        │
   │  Loop             │  │  Delegation       │
   │                   │  │                   │
   │  bash, read_file, │  │  spawn_agent →    │
   │  grep, http_get,  │  │  recon-specialist │
   │  run_module,      │  │  vuln-specialist  │
   │  run_flow, jq,    │  │  web-specialist   │
   │  save_content … │  │  network-spec.    │
   │                   │  │  report-spec.     │
   └────────┬─────────┘  └────────┬─────────┘
            │                      │
            ▼                      ▼
   ┌──────────────────────────────────────────┐
   │              Runner Layer                 │
   │  HostRunner / DockerRunner / SSHRunner    │
   │  Executes commands, captures output       │
   └──────────────────────────────────────────┘
```

### Decision Flow

```
START
  │
  ▼
[Plan Stage] ── brain reads target, creates attack plan
  │
  ▼
[Reasoning Loop] ◄──────────────────────────────┐
  │                                              │
  ├─ Q1: What do I know?                         │
  ├─ Q2: What am I looking for?                  │
  ├─ Q3: Best approach? ──► Tool call            │
  ├─ Q4: What could go wrong?                    │
  └─ Q5: What is unusual? ──► Adapt strategy     │
  │                                              │
  ▼                                              │
[Execute Action]                                 │
  ├─ Direct tool call (bash, http_get, etc.)     │
  ├─ Module execution (run_module)               │
  └─ Sub-agent delegation (spawn_agent)          │
  │                                              │
  ▼                                              │
[Analyze Results]                                │
  ├─ New findings? ──► Update attack surface map │
  ├─ Anomalies? ──► Investigate further ─────────┘
  ├─ Phase complete? ──► Move to next phase ─────┘
  └─ Stop condition met? ──► Generate report
  │
  ▼
[Report Generation]
  │
  ▼
END
```

### Memory and Persistence

The brain agent maintains conversation context across iterations using a sliding window:

- **`memory.max_messages`** — Maximum messages retained in context. Older messages are truncated.
- **`memory.summarize_on_truncate`** — When true, the agent summarizes truncated messages before discarding them, preserving key findings.
- **`memory.persist_path`** — Save conversation history to disk for post-scan analysis.
- **`memory.resume_path`** — Resume a previous scan by loading saved conversation state.

Persistence paths typically point to the workspace output directory:
```yaml
memory:
  max_messages: 50
  summarize_on_truncate: true
  persist_path: "{{Output}}/agent/conversation.json"
```

---

## Configuration

### LLM Provider Setup

#### OpenAI (recommended)

```yaml
llm_config:
  llm_providers:
    - provider: openai
      base_url: "https://api.openai.com/v1/chat/completions"
      auth_token: ""  # Uses OPENAI_API_KEY env var
      model: "gpt-4.1"
  enabled_tool_call: true
  max_tokens: 4096
  temperature: 0.3
```

```bash
export OPENAI_API_KEY=sk-xxx
```

#### Ollama (local, no API costs)

```yaml
llm_config:
  llm_providers:
    - provider: ollama
      base_url: "http://localhost:11434/v1/chat/completions"
      auth_token: ""
      model: "llama3:70b"
  enabled_tool_call: true
  max_tokens: 4096
  temperature: 0.3
```

```bash
# Install and start Ollama
curl -fsSL https://ollama.com/install.sh | sh
ollama pull llama3:70b
ollama serve
```

#### Anthropic Claude

```yaml
llm_config:
  llm_providers:
    - provider: anthropic
      base_url: "https://api.anthropic.com/v1/messages"
      auth_token: ""  # Uses ANTHROPIC_API_KEY env var
      model: "claude-sonnet-4-20250514"
  enabled_tool_call: true
  max_tokens: 4096
  temperature: 0.3
```

```bash
export ANTHROPIC_API_KEY=sk-ant-xxx
```

#### Multi-Provider Rotation (recommended for reliability)

```yaml
llm_config:
  llm_providers:
    - provider: openai
      base_url: "https://api.openai.com/v1/chat/completions"
      auth_token: ""
      model: "gpt-4.1"
    - provider: openai
      base_url: "https://api.openai.com/v1/chat/completions"
      auth_token: ""
      model: "o4-mini"
    - provider: ollama
      base_url: "http://localhost:11434/v1/chat/completions"
      auth_token: ""
      model: "llama3:70b"
```

Providers are tried in order. If the primary returns an error or hits a rate limit, the next provider is used automatically.

### Tool Paths

Security tool binaries are resolved via `{{Binaries}}` which maps to:
```
~/osmedeus-base/external-binaries/
```

Install all tools:
```bash
osmedeus install binary --all

# Or check what's installed
osmedeus install binary --all --check
```

### Timeout and Threading

```bash
# Set scan timeout (default: none)
osmedeus run -f ai-scan -t target.com --timeout 2h

# Use aggressive threading
osmedeus run -f ai-scan -t target.com --tactic aggressive

# Use gentle/stealthy threading
osmedeus run -f ai-redteam -t target.com --tactic gently
```

Thread counts are configured in `osm-settings.yaml` under `scan_tactic`:
```yaml
scan_tactic:
  aggressive: 30   # Fast, more network noise
  default: 10      # Balanced
  gently: 3        # Slow, stealthy
```

---

## Examples

### Bug Bounty Scan with Custom Scope

```bash
# Single target
osmedeus run -f ai-scan -t hackerone.com

# Multiple targets from file
osmedeus run -f ai-scan -T scope.txt -c 3

# Exclude specific modules from the flow
osmedeus run -f ai-scan -t hackerone.com -x report/generate-report

# Fuzzy-exclude all network modules
osmedeus run -f ai-scan -t hackerone.com -X network
```

### Network-Only Assessment

```bash
# Run network modules in sequence
osmedeus run -m network/service-enum -m network/smb-audit -t 192.168.1.0/24

# With custom timeout
osmedeus run -m network/service-enum -t 10.0.0.0/16 --timeout 4h
```

### Running Specific Modules Manually

```bash
# Subdomain enumeration only
osmedeus run -m recon/subdomain-enum -t example.com

# Nuclei vulnerability scan
osmedeus run -m vuln/nuclei-scan -t example.com

# SSL/TLS audit
osmedeus run -m vuln/ssl-audit -t example.com

# Port scanning
osmedeus run -m recon/port-scan -t 192.168.1.1
```

### Resuming Interrupted Scans

The brain agent persists its conversation state when `memory.persist_path` is configured. To resume:

```bash
# The agent checks for existing conversation.json in the workspace
# and resumes where it left off if the same target is re-run
osmedeus run -f ai-scan -t example.com
```

### Exporting and Sharing Results

```bash
# Export workspace as a ZIP archive
osmedeus snapshot export example.com

# Import from file or URL
osmedeus snapshot import /path/to/snapshot.zip
osmedeus snapshot import https://example.com/snapshots/scan.zip

# List available snapshots
osmedeus snapshot list
```

---

## Troubleshooting

### Common Issues

#### API Key Not Set

```
Error: LLM provider returned 401 Unauthorized
```

**Fix:** Ensure your API key is exported:
```bash
export OPENAI_API_KEY=sk-xxx

# Verify it's set
echo $OPENAI_API_KEY
```

For Docker, pass it via the environment:
```bash
OPENAI_API_KEY=sk-xxx docker compose -f build/docker/docker-compose.ai.yaml up -d
```

#### Tool Not Found

```
Error: exec: "subfinder": executable file not found in $PATH
```

**Fix:** Install missing tools:
```bash
# Install all tools
osmedeus install binary --all

# Check which tools are installed
osmedeus install binary --all --check

# Install a specific tool
osmedeus install binary --name subfinder

# Add tool paths to your shell
osmedeus install env
```

#### LLM Timeout

```
Error: LLM request timed out after 120s
```

**Fix:** Increase the timeout in your settings:
```yaml
llm_config:
  timeout: 300s      # 5 minutes
  max_retries: 5     # More retries for transient failures
```

Or use a faster model as fallback:
```yaml
llm_config:
  llm_providers:
    - provider: openai
      model: "gpt-4.1"       # Primary (slower, smarter)
    - provider: openai
      model: "o4-mini"        # Fallback (faster, cheaper)
```

#### Rate Limit Errors

```
Error: LLM provider returned 429 Too Many Requests
```

**Fix:** Add a fallback provider. The engine automatically rotates to the next provider on rate limit errors:
```yaml
llm_config:
  llm_providers:
    - provider: openai
      model: "gpt-4.1"
    - provider: ollama
      base_url: "http://localhost:11434/v1/chat/completions"
      model: "llama3:70b"
```

#### Brain Seems Stuck or Looping

**Fix:** Check the max_iterations setting. If the brain hits its iteration limit, it stops and reports what it found. Increase it for complex targets:

```yaml
steps:
  - name: brain
    type: agent
    max_iterations: 30    # Default is usually 10-20
```

### Checking Brain Logs

```bash
# View the brain's conversation history (if persist_path is set)
cat ~/workspaces-osmedeus/example.com/agent/conversation.json | jq .

# View real-time scan output
osmedeus run -f ai-scan -t example.com -v

# Check workspace artifacts
ls -la ~/workspaces-osmedeus/example.com/
```

### Increasing Verbosity

```bash
# Verbose output — shows brain reasoning and tool calls
osmedeus run -f ai-scan -t example.com -v

# With progress bar
osmedeus run -f ai-scan -t example.com -G

# View all available workflows
osmedeus workflow list

# Validate a workflow before running
osmedeus workflow validate ai-scan
```

---

## Further Reading

- [Cloud Usage Guide](cloud-usage-guide.md) — Distributed scanning across cloud providers
- [Cloud Quick Reference](cloud-quick-reference.md) — Common cloud commands
- [API Documentation](api/) — REST API endpoints with curl examples
- Settings template: `public/presets/ai-scan-settings.yaml`
- Brain prompt: `prompts/brain/hacker-brain.txt`
- Profile templates: `prompts/profiles/`
