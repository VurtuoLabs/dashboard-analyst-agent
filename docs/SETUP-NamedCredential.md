# Beginner's Guide: Creating the Named Credential `Salesforce_API`

For the agent to read the "contents of a dashboard," it needs a "pass" from within Salesforce
to call its own Salesforce data via the API. That's the **Named Credential `Salesforce_API`**.
These are the steps that were actually built and **verified to work** in this org
(`<YOUR_ORG_ID>` / `<YOUR_ORG_ALIAS>`).

> Your org URL (used throughout these steps): `https://<YOUR_ORG_ALIAS>.my.salesforce.com`
> ⚠ The consumer key and secret are sensitive information. Do not post them to GitHub/Slack/etc.

## Big picture (3 parts + one click at the end)
```
①External Client App → ②Auth. Provider → ③Named Credential → ④Click "Allow" once
 (issuer of the pass)      (how authorization works)   (the pass Apex uses)   (★the only manual step that can't be automated)
```

---

## ① External Client App
Setup → Quick Find "External Client" → **External Client App Manager** → **New**
- Name: `Self Callout` / API Name: `Self_Callout` / Contact Email: yourself
- Check **Enable OAuth Settings**
- Callback URL (placeholder): `https://login.salesforce.com/services/authcallback`
- Selected OAuth Scopes: `api` (Manage user data via APIs) and `refresh_token, offline_access` (Perform requests at any time)
- Create

## ② Note down the Consumer Key and Secret
Self Callout → **Settings** → **OAuth Settings** → **Consumer Key and Secret** button
(enter the identity verification code if prompted) → copy and save the **Consumer Key** and **Consumer Secret**.

## ③ Auth. Provider
Setup → Quick Find "Auth. Providers" → **New**
- Provider Type: **Salesforce**
- Name: `Self Auth` / URL Suffix: `Self_Auth`
- Consumer Key / Consumer Secret: paste the values you saved in step ②
- **🚨 Default Scopes: `api refresh_token`** (single half-width space between them; omitting this causes `invalid_scope`)
- Save → note down the **Callback URL** shown under **Salesforce Configuration** at the bottom:
  `https://<YOUR_ORG_ALIAS>.my.salesforce.com/services/authcallback/Self_Auth`

## ④ Replace the app's callback URL with the real one
Go back to Self Callout from step ① → Settings → OAuth Settings → **Edit** →
**overwrite** the Callback URL with the value you noted in step ③ (`…/services/authcallback/Self_Auth`) → Save.
(Also confirm that **Selected OAuth Scopes** includes both `api` and `refresh_token, offline_access`)

## ⑤ Named Credential
Setup → Quick Find "Named Credentials" → **New (choose "New Legacy" from the ▼ dropdown)**
| Field | Value |
|---|---|
| Label / Name | `Salesforce_API` (★ Apex calls this name, so it must be exact) |
| URL | `https://<YOUR_ORG_ALIAS>.my.salesforce.com` |
| Identity Type | Named Principal |
| Authentication Protocol | OAuth 2.0 |
| Authentication Provider | `Self Auth` |
| Scope | leave blank |
| Start Authentication Flow on Save | ✅ checked |

Save → login/authorization screen → **click "Allow"** → success once the **Authentication Status** shows **"Authenticated"**.

---

## ❗ Troubleshooting: if you get `redirect_uri_mismatch`
- Almost every cause is a timing issue where "the app save from step ④ hasn't propagated yet."
- If the configuration is correct (the callback URL ends with `/Self_Auth`), **wait 2-3 minutes**, then go back to
  the edit screen from step ⑤, re-check "Start Authentication Flow on Save," and **save again** — this should resolve it.
- If it still doesn't work, disable your browser's popup blocker and try again.

## ✅ Verification (proven working in this org)
- Direct Apex: passing a Lightning URL to `dashboardIdOrUrl` → **callouts: 1 / success=true**,
  turns the "Enablement Dashboard" into Markdown in on-screen order.
- Agent: "Analyze this dashboard <URL>" → replies in English with Overview/Key KPIs/Trends/Recommended Actions.

## Permissions (already handled via CLI)
Permission to execute the Apex is included in the permission set `Analytics_Dashboard_Agent`, which has already been assigned to the running user.
To assign it to other users:
```bash
sf org assign permset --target-org <YOUR_ORG_ALIAS> --name Analytics_Dashboard_Agent --on-behalf-of <username>
```
