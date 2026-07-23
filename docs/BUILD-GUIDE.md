# BUILD GUIDE, Agentforce × Dashboard Analysis Agent

When a user has a Lightning dashboard open and says "Analyze this dashboard,"
the agent reads the contents and returns an **Overview / Key KPIs / Trends & Notable Patterns / Recommended Actions** summary in English.
Built with the **new builder (Agent Script / AiAuthoringBundle)**, in a version with **zero callout/OAuth setup**.

- Target org: `<YOUR_ORG_ID>` (alias `<YOUR_ORG_ALIAS>`)
- Agent: `Dashboard_Analyst` (**published, v1 Active**)
- API version: 67.0 / CLI: `@salesforce/cli 2.136.8`

---

## 0. What this solves (the essence of the design decision)

The original setup (Slack canvas version) used a method where the **Analytics REST API was called via a self-callout through a Named Credential**, which required **a large amount of manual setup**: an External Credential, an Auth Provider, and browser "Allow" OAuth consent.

After investigation and verification on the org, it turned out this could be **completely replaced with native Apex**:

| Approach | Manual setup | Adopted |
|---|---|---|
| (a) Named Credential + OAuth self-callout | Requires External Credential, Auth Provider, browser Allow | No, old version |
| (b) session-id self-callout + Remote Site | Requires Remote Site + unstable because `getSessionId()` becomes null asynchronously | No |
| **(c) Native `Reports.ReportManager`** | **None** (no callouts, no Named Credential) | Yes, **adopted** |

**Verification log (anonymous Apex execution on the org)**:
```
Components: 12 / Distinct report ids: 6
Report ...RaVoMAK grand total label = 0
Number of callouts: 0 out of 100   ← retrieved successfully with 0 callouts
```

Since `DashboardComponent` can be queried via SOQL (`DashboardId` → `CustomReportId`),
the dashboard-to-report mapping can also be resolved natively at runtime.

---

## 1. Architecture

```
[User: Lightning dashboard screen]
        │ "Analyze this dashboard" (+URL)
        ▼
[Agentforce Employee Agent: Dashboard_Analyst]   ← AiAuthoringBundle (.agent)
   ├ start_agent agent_router  (intent classification)
   └ subagent dashboard_analysis
        │ action: analyze_dashboard
        ▼
[Apex: AnalyzeDashboardNative]   ← invocable, with sharing, callout 0
   1. SELECT ... FROM Dashboard WHERE Id = :id
   2. SELECT CustomReportId FROM DashboardComponent WHERE DashboardId = :id
   3. Reports.ReportManager.runReport(reportId, false)  ×N
   4. factMap('T!T') + getGroupingsDown() → markdown summary
        ▼
[Agent responds in English with Overview/KPIs/Trends/Recommended Actions]
```

### Context Engineering design (reflecting principles from 3 reference articles)
- **Just-in-time**: the large factMap is pruned on the Apex side to `MAX_REPORTS=25 / MAX_GROUPINGS_PER_REPORT=12` before being passed along.
- **Minimal tools**: only one action, `analyze_dashboard` (avoiding tool bloat).
- **Compact summary**: returns a markdown summary rather than raw JSON (saving attention budget).
- **Right altitude**: instructions are kept at the business-framework level (Overview/KPIs/Trends/Recommendations).
- **Loop prevention / grounding**: `last_summary` suppresses re-execution, output field names are explicit, `show_command` is prohibited, and altering numeric values is prohibited.

---

## 2. Component list

| Type | Name | Role | Status |
|---|---|---|---|
| Apex (invocable) | `AnalyzeAnalyticsAssetAction` | **Current backing** (the real Slack canvas implementation). Converts the Dashboard Results API into Markdown in the same order as the screen layout (supports metrics/charts/tables/scatter plots/rich text headings). `dashboardIdOrUrl` path = Named Credential, `rawPayloadJson` path = no callout required | Deployed / 4 tests pass / verified with real data (callout 0) |
| Apex (invocable) | `AnalyzeDashboardNative` | Alternative (Reports API, completely callout/Named Credential free). Works with zero setup but does not reproduce the dashboard's layout order or chart types | Deployed / 6 tests pass |
| AiAuthoringBundle | `Dashboard_Analyst` | The agent itself (Employee Agent). Calls `AnalyzeAnalyticsAssetAction` with `dashboardIdOrUrl` | Published / **v3 Active** |
| PermissionSet | `Analytics_Dashboard_Agent` | Both Apex classes + agentAccess | Deployed / assigned to running user |

> **Two backing options are provided**: the real canvas implementation (`AnalyzeAnalyticsAssetAction`) = reproduces the screen exactly as in the GIF but requires a Named Credential / `AnalyzeDashboardNative` = zero setup but simplified. You can switch between them just by swapping the agent's `target:` depending on requirements.

---

## 3. Reproduction steps (to build this in a different org from this repo)

Everything can be done via the CLI. `<alias>` is the target org.

```bash
# 1) Deploy Apex and permissions
sf project deploy start --target-org <alias> \
  --metadata ApexClass:AnalyzeDashboardNative ApexClass:AnalyzeDashboardNativeTest \
             PermissionSet:Analytics_Dashboard_Agent

# 2) Apex tests (confirm 6 pass)
sf apex run test --target-org <alias> \
  --class-names AnalyzeDashboardNativeTest --synchronous --result-format human

# 3) Validate the agent (AiAuthoringBundle) → deploy
sf agent validate authoring-bundle --json --api-name Dashboard_Analyst
sf project deploy start --target-org <alias> --metadata AiAuthoringBundle:Dashboard_Analyst

# 4) Verify behavior with live preview (0 callouts, verified with real data)
sf agent preview start --json --authoring-bundle Dashboard_Analyst --use-live-actions
sf agent preview send  --json --authoring-bundle Dashboard_Analyst \
  --session-id <SID> -u "Analyze this dashboard https://<org>/lightning/r/Dashboard/<01Z...>/view"

# 5) publish → activate (this generates the Bot / BotVersion / GenAiPlannerBundle)
sf agent publish authoring-bundle --json --api-name Dashboard_Analyst
sf agent activate --json --api-name Dashboard_Analyst

# 6) Grant Apex execution permission to the user
sf org assign permset --target-org <alias> --name Analytics_Dashboard_Agent
```

> ⚠️ Make sure `sourceApiVersion` is **67.0**. If it's lower, the AiAuthoringBundle
> will fail with `Not available for deploy for this API version`.

---

## 4. Displaying it on screen (enabling the panel), CLI-automated + remaining manual steps

### Key prerequisites (the correct mechanism revealed by investigation)
- The Agentforce assistant is opened via the **icon in the top-right of the Lightning header (global)**.
  **It is not something you expose via an app-specific Utility Bar or App Builder component** (no such standard component exists).
- What appears in the header panel is a **single org-wide slot called `Copilot_for_Salesforce` ("Agentforce (Default)")**.

### ✅ Automated via CLI (already done in this org)
```bash
# 1) Enable the panel feature (this sets up the prerequisite for the icon to appear in the header)
#    Set force-app/main/default/settings/EinsteinCopilot.settings-meta.xml's
#    <enableEinsteinGptCopilot> to true:
sf project deploy start --target-org <alias> --metadata Settings:EinsteinCopilot
#    → After deployment, the built-in default agent "Copilot_for_Salesforce (Agentforce (Default))" appears

# 2) Assign required permissions to the users who will use it (needed for the header icon to display and be usable)
sf org assign permset --target-org <alias> \
  --name CopilotSalesforceUser EinsteinGPTPromptTemplateUser CopilotSalesforceAdmin
#    CopilotSalesforceUser         = "Access Agentforce Default Agent"
#    EinsteinGPTPromptTemplateUser = "Prompt Template User"
#    CopilotSalesforceAdmin        = "Agentforce Default Admin" (for administrators)

# 3) Also assign action execution permission (Apex) (as mentioned earlier)
sf org assign permset --target-org <alias> --name Analytics_Dashboard_Agent
```
> ⚠️ `Copilot_for_Salesforce` "cannot have its activation status changed because it is the default agent" (`sf agent activate` is not possible for it).
> Once the panel feature is enabled, this slot automatically becomes usable.

### 🖐 Remaining manual steps (UI required), check after a browser reload

**STEP A. Check whether the icon appears in the header**
- Log in as the target user → **hard reload** the browser.
- If the **Agentforce icon (speech bubble/star)** has been added to the top-right icon row (★ / + / ☁ / ? / ⚙ / 🔔 / avatar), you're good. Clicking it opens the panel.
- If it doesn't appear: wait for the permission set (STEP 2) to take effect (a few minutes), or check under [Setup] > **Einstein Setup / Generative AI** whether "Turn on Einstein" is off.

**STEP B. Make the agent shown in the panel use the `Dashboard Analyst` content (UI)**
The panel displays the default slot `Copilot_for_Salesforce`. There are two ways to add your custom analysis feature to it:
- **(Recommended, fastest)** Go to [Setup] > **Agentforce Studio** > **Agentforce Agents** > open `Agentforce (Default)`,
  **add a "Dashboard Analysis" topic with the action `Analyze Dashboard (Native)` (apex://AnalyzeDashboardNative) under Topics** → save.
  This makes dashboard analysis available from the default panel.
- **(Alternative)** On the same screen, use "**Migrate to an Agentforce Employee Agent**" to promote `Dashboard_Analyst` to the default panel agent.
  Note: in the permission set's `agentAccesses` (`<agentName>`), both `Copilot_for_Salesforce` and `Dashboard_Analyst`
  are already linked under "Enabled Agent Access" (CLI deployment succeeded).

> In short, **panel enablement, permission assignment, and agent linkage needed to "open it on screen" are all done via CLI**.

> Everything else (Apex, agent definition, publish, activate, testing) is **entirely done via CLI**.
> The **External Credential / Auth Provider / Named Credential / browser OAuth "Allow" consent** that the old version required is **completely unnecessary**.

### 🚨 If the panel shows "Something went wrong. Refresh the conversation"
This is a symptom where the panel UI (Astro + "Let's chat!") appears, but session initialization fails. Causes and remedies (investigated and verified):

1. **[Most likely, UI required] Metadata activation alone may not trigger server-side provisioning in the Setup UI.**
   - Under [Setup] > **Einstein Setup (Einstein Setup / Generative AI)**, check "**Turn on Einstein**." Even if it's On, toggle it Off → Save → On again to re-trigger provisioning.
   - Turn on the "**Turn on Agentforce**" toggle at the top of the [Setup] > **Agentforce Agents** page.
     Note: the default agent `Copilot_for_Salesforce` has no individual activate action (`sf agent activate` is not possible), so **this org-level toggle is effectively the "activation" itself**.
   - If the "Agentforce Agents" node doesn't appear in Setup, generative AI is not yet enabled, redo the Einstein steps above.
2. **[Session cache]** Since permissions were granted after login, log out and log back in once **(or fully restart the browser)** before opening the panel.
3. **[Provisioning delay]** Especially for trial/demo orgs, this error can appear for a few minutes right after activation. **Wait 5–15 minutes and retry**.
4. **[Enabled Agent Access]** → Already linked via CLI (`agentAccesses`) in this repo. To confirm via the UI,
   check [Setup] > Permission Sets > the relevant set > whether `Agentforce (Default)` is listed under "**Enabled Agent Access**."

> Summary: **All the enablement, permissions, and linkage that can be done via CLI have been completed**. The remaining possibilities are
> **(1) the Setup UI's "Turn on Agentforce" toggle, (2) re-login, (3) waiting for provisioning**, all three are UI/timing factors.

---

## 5. The mechanism for "recognizing the dashboard on screen" (important, verification results)

The ideal experience is "automatically analyze the currently open dashboard without pasting a URL." Here is the **conclusion verified on a real environment**:

### Verification results (facts)
- Using `source: @context.currentRecordId` in an Agent Script linked variable causes, in this org / API 67.0,
  **`sf agent validate` to reject it with a compile error** (`'source' must reference one of: @MessagingSession, @MessagingEndUser, @VoiceCall`).
- Even according to field validation info, `@context.currentRecordId` only resolves **when an Employee Agent is embedded in a LEX "record page,"**
  and since a **Dashboard page (`/lightning/r/Dashboard/{01Z}/view`) is not a record page**, there is no guarantee it returns an id.
- The Agent API's default context variables are only `Id` / `EndUserId` / `EndUserLanguage`. There is **no officially existing mechanism**
  to automatically inject an arbitrary page's recordId into the standard panel.

→ Conclusion: **"Automatically recognizing the on-screen dashboard without pasting a URL" is not achievable with currently verified features.**

### The reliable approach adopted (v2, verified working on a real environment)
1. If the user includes a **URL or ID (01Z…)** in their utterance, analysis happens immediately. The `analyze_dashboard` input `dashboardIdOrUrl`
   is captured via LLM slot-filling (`with dashboardIdOrUrl = ...`) → finalized by Apex's `extractId()` (regex `01Z[a-zA-Z0-9]{12,15}`).
2. If there's no URL/ID, the agent **does not guess** and instead specifically guides the user:
   "Please paste the URL from your address bar (the 01Z… ID alone is fine too)" (safe grounding). Once pasted, analysis happens immediately.
3. Follow-ups are answered based on `last_summary` without re-executing.

> Real-environment log: "Analyze My forecast" → URL guidance / URL pasted → read "Enablement Dashboard" and responded with all 4 sections (callout 0).

### If "auto-recognition without a URL" is implemented in the future (not yet implemented, options)
- Build a **custom LWC panel** (utility bar) that reads the current page id via `@api recordId` / `pageReference`,
  and passes it as a **custom context variable (visibility External)** when starting a session via the Agent API. This does not depend on the standard panel's auto-injection.
- If the experience is changed to **assume a record page**, using `@context.currentRecordId` (valid only on record pages) is an option,
  but it does not fit this project's requirement of viewing dashboards.

---

## 6. Verified behavior (authoring-bundle live preview)

| Case | Result |
|---|---|
| "Analyze this + URL" | Executed `analyze_dashboard` once → read "Enablement Dashboard" (12 components) and responded in English with Overview/KPIs/Trends/Recommendations. trace: Transition×1, Function×1, Guardrails=pass, callouts=0 |
| Follow-up "What's the most common one?" | Answered from the most recent summary without re-executing (loop prevention OK) |
| "Analyze" without a URL | Did not guess, and politely requested the URL (grounding safety OK) |

---

## 7. Enabling the Slack canvas approach (real Apex), Named Credential

The current backing `AnalyzeAnalyticsAssetAction` (the real canvas implementation)'s `dashboardIdOrUrl` path
calls your org's own Dashboard Results API via the **Named Credential `Salesforce_API`**. Without it,
the agent politely returns an error saying "named credential 'Salesforce_API' might not exist" (confirmed on a real environment).

### 🖐 Manual steps (UI required, only the OAuth "Allow" click cannot be automated)
As described in canvas §1. The shortest path:
1. Create an **External Client App** (or Connected App) and enable OAuth, with scope = `api refresh_token offline_access`, and note the Consumer Key/Secret.
2. Create an **Auth Provider** (Salesforce type) named `Self_Auth`. **Set Default Scopes to `api refresh_token`, space-separated** (missing this causes invalid_scope). Note the Callback URL.
3. Overwrite the External Client App's Callback URL with the Callback URL from step 2.
4. Create a **Named Credential** `Salesforce_API` (Legacy). URL = your org's my.salesforce.com domain, Authentication Protocol = OAuth 2.0, Auth Provider = `Self_Auth`, start the authentication flow on save → **Allow** → confirm "Authenticated."
   - ⚠ Disable your browser's popup blocker.
5. Now, asking the agent with `dashboardIdOrUrl` will return real-data, screen-ordered Markdown.

> ⚠ The Named Credential's OAuth "Allow" click is the only manual step that cannot be automated headlessly.
> If you want to avoid this, use the alternative approaches below (rawPayload / native Reports).

### ✅ Facts confirmed through verification (real environment)
- The **canvas Apex renderer itself runs with 0 callouts**. By passing Dashboard Results JSON into `rawPayloadJson`,
  it was able to convert the real dashboard "Enablement Dashboard" (12 components) into Markdown **in the exact order of the screen's headings** (confirmed callouts: 0).
- In other words, as long as a "path for passing in JSON" is provided, canvas-quality output is achievable even without a Named Credential.

### Alternative approaches (no Named Credential needed, both close to zero setup)
- **A. `rawPayloadJson` + custom LWC panel**: an LWC reads the currently displayed dashboard id via `@api recordId` etc.,
  fetches the Dashboard Results JSON, and passes it into `rawPayloadJson`. This achieves both goals of canvas, **no OAuth needed + automatic on-screen id capture** (not yet implemented, next step).
- **B. `AnalyzeDashboardNative` (Reports API)**: simply set the agent's `target:` back to `apex://AnalyzeDashboardNative`.
  No Named Credential or Remote Site needed, works immediately, but it's a simplified version that doesn't reproduce the screen's layout order or chart types.

---

## 8. Known caveats
- `Reports.ReportManager.runReport` (Alternative B) has a limit of **500 synchronous calls/hour/org**. One dashboard consumes as many calls as it has reports.
- The canvas Apex's `dashboardIdOrUrl` path performs a **live fetch** from the Dashboard Results API. It requires a Named Credential.
- Published preview via `--api-name` can sometimes fail due to CLI-side running-user resolution, but the agent remains active and usable in practice (verified via authoring-bundle live preview).
