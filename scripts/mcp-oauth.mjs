import { Buffer } from "node:buffer";
import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import {
  GOOGLE_SCOPES,
  SLACK_READ_SCOPES,
  loadMcpSecrets,
  saveProviderSecrets,
  secretDir
} from "./mcp-secret-store.mjs";

const CONNECT_PROVIDERS = new Set(["google", "slack", "notion"]);
const STATE_TTL_MS = 10 * 60 * 1000;
const HTML_HEADERS = { "content-type": "text/html; charset=utf-8" };
const NOTION_VERSION = "2022-06-28";

export async function handleOAuthRoute(app, request, response, env = process.env) {
  const url = new URL(request.url, `http://${request.headers.host ?? "127.0.0.1"}`);
  const provider = connectProviderForApp(app);
  if (!CONNECT_PROVIDERS.has(provider)) return false;
  if (request.method !== "GET") return false;
  if (url.pathname === "/connect") {
    await startOAuthConnect({ app, provider, request, response, url, env });
    return true;
  }
  if (url.pathname === "/oauth/callback") {
    await finishOAuthConnect({ provider, request, response, url, env });
    return true;
  }
  return false;
}

export function connectProviderForApp(app) {
  if (app === "gmail" || app === "google-workspace" || app === "google-drive") return "google";
  return app;
}

export function callbackPath(provider) {
  return `/oauth/callback`;
}

export async function buildConnectUrl({ app, provider = connectProviderForApp(app), origin, url, env = process.env }) {
  const secrets = await loadMcpSecrets(env);
  const redirectUri = `${origin}${callbackPath(provider)}`;
  const pending = {
    app,
    provider,
    redirectUri,
    createdAt: Date.now(),
    parentPageId: url?.searchParams.get("parent_page_id") ?? undefined,
    databaseId: url?.searchParams.get("database_id") ?? undefined
  };
  const state = await savePendingState(pending, env);
  if (provider === "google") {
    requireConnectKeys(provider, {
      GOOGLE_CLIENT_ID: secrets.google.clientId,
      GOOGLE_CLIENT_SECRET: secrets.google.clientSecret
    });
    return googleAuthUrl({ clientId: secrets.google.clientId, redirectUri, state });
  }
  if (provider === "slack") {
    requireConnectKeys(provider, {
      SLACK_CLIENT_ID: secrets.slack.clientId,
      SLACK_CLIENT_SECRET: secrets.slack.clientSecret
    });
    return slackAuthUrl({ clientId: secrets.slack.clientId, redirectUri, state });
  }
  if (provider === "notion") {
    requireConnectKeys(provider, {
      NOTION_CLIENT_ID: secrets.notion.clientId,
      NOTION_CLIENT_SECRET: secrets.notion.clientSecret
    });
    return notionAuthUrl({ clientId: secrets.notion.clientId, redirectUri, state });
  }
  throw new Error(`Unsupported OAuth provider: ${provider}`);
}

async function startOAuthConnect({ app, provider, request, response, url, env }) {
  const origin = bridgeOrigin(request, url);
  try {
    const authUrl = await buildConnectUrl({ app, provider, origin, url, env });
    if (url.searchParams.get("format") === "json") {
      return sendJson(response, 200, { ok: true, app, provider, authUrl, redirectUri: `${origin}${callbackPath(provider)}` });
    }
    response.writeHead(302, { location: authUrl });
    response.end();
  } catch (error) {
    if (url.searchParams.get("format") === "json") {
      return sendJson(response, 400, { ok: false, app, provider, error: error.message, setup: setupInstructions(provider, origin) });
    }
    sendHtml(response, 400, setupPage({ app, provider, origin, error: error.message }));
  }
}

async function finishOAuthConnect({ provider, response, url, env }) {
  try {
    const error = url.searchParams.get("error");
    if (error) throw new Error(`${provider} OAuth rejected: ${error}`);
    const code = url.searchParams.get("code");
    if (!code) throw new Error(`${provider} OAuth callback is missing code.`);
    const state = url.searchParams.get("state");
    const pending = await readPendingState(state, env);
    if (pending.provider !== provider) throw new Error(`OAuth state provider mismatch: expected ${pending.provider}, got ${provider}.`);
    const secrets = await loadMcpSecrets(env);
    const result = await exchangeOAuthCode({ provider, code, redirectUri: pending.redirectUri, secrets });
    await saveOAuthResult({ provider, result, pending, secrets, env });
    sendHtml(response, 200, successPage(provider));
  } catch (error) {
    sendHtml(response, 400, failurePage(provider, error.message));
  }
}

async function exchangeOAuthCode({ provider, code, redirectUri, secrets }) {
  if (provider === "google") return exchangeGoogleCode({ code, redirectUri, google: secrets.google });
  if (provider === "slack") return exchangeSlackCode({ code, redirectUri, slack: secrets.slack });
  if (provider === "notion") return exchangeNotionCode({ code, redirectUri, notion: secrets.notion });
  throw new Error(`Unsupported OAuth provider: ${provider}`);
}

async function saveOAuthResult({ provider, result, pending, secrets, env }) {
  if (provider === "google") {
    if (!result.refresh_token && !secrets.google.refreshToken) {
      throw new Error("Google did not return a refresh token. Try /connect again and approve consent, or remove the old app grant first.");
    }
    await verifyGoogleAccess(result.access_token);
    await saveProviderSecrets("google", {
      clientId: secrets.google.clientId,
      clientSecret: secrets.google.clientSecret,
      refreshToken: result.refresh_token ?? secrets.google.refreshToken,
      accessToken: result.access_token,
      calendarId: secrets.google.calendarId,
      calendarTimeZone: secrets.google.calendarTimeZone,
      verifiedAt: new Date().toISOString()
    }, env);
    return;
  }
  if (provider === "slack") {
    const userToken = result.authed_user?.access_token;
    const botToken = result.access_token?.startsWith("xoxb-") ? result.access_token : undefined;
    if (!userToken && !botToken) throw new Error("Slack OAuth did not return a readable user or bot token.");
    await verifySlackAccess(userToken ?? botToken);
    await saveProviderSecrets("slack", {
      clientId: secrets.slack.clientId,
      clientSecret: secrets.slack.clientSecret,
      userToken,
      botToken,
      teamId: result.team?.id,
      verifiedAt: new Date().toISOString()
    }, env);
    return;
  }
  if (provider === "notion") {
    await verifyNotionAccess(result.access_token);
    await saveProviderSecrets("notion", {
      clientId: secrets.notion.clientId,
      clientSecret: secrets.notion.clientSecret,
      token: result.access_token,
      parentPageId: pending.parentPageId ?? secrets.notion.parentPageId,
      databaseId: pending.databaseId ?? secrets.notion.databaseId,
      titleProperty: secrets.notion.titleProperty,
      workspaceId: result.workspace_id,
      workspaceName: result.workspace_name,
      botId: result.bot_id,
      verifiedAt: new Date().toISOString()
    }, env);
  }
}

function googleAuthUrl({ clientId, redirectUri, state }) {
  return `https://accounts.google.com/o/oauth2/v2/auth?${new URLSearchParams({
    client_id: clientId,
    redirect_uri: redirectUri,
    response_type: "code",
    access_type: "offline",
    include_granted_scopes: "true",
    prompt: "consent",
    state,
    scope: GOOGLE_SCOPES.join(" ")
  })}`;
}

function slackAuthUrl({ clientId, redirectUri, state }) {
  return `https://slack.com/oauth/v2/authorize?${new URLSearchParams({
    client_id: clientId,
    user_scope: SLACK_READ_SCOPES.join(","),
    redirect_uri: redirectUri,
    state
  })}`;
}

function notionAuthUrl({ clientId, redirectUri, state }) {
  return `https://api.notion.com/v1/oauth/authorize?${new URLSearchParams({
    client_id: clientId,
    response_type: "code",
    owner: "user",
    redirect_uri: redirectUri,
    state
  })}`;
}

async function exchangeGoogleCode({ code, redirectUri, google }) {
  const payload = await fetchJson("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: google.clientId,
      client_secret: google.clientSecret,
      redirect_uri: redirectUri,
      grant_type: "authorization_code"
    })
  }, "Google OAuth token exchange");
  return payload;
}

async function exchangeSlackCode({ code, redirectUri, slack }) {
  const payload = await fetchJson("https://slack.com/api/oauth.v2.access", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: slack.clientId,
      client_secret: slack.clientSecret,
      redirect_uri: redirectUri
    })
  }, "Slack OAuth token exchange");
  if (!payload.ok) throw new Error(`Slack OAuth token exchange failed: ${payload.error ?? "unknown_error"}`);
  return payload;
}

async function exchangeNotionCode({ code, redirectUri, notion }) {
  const payload = await fetchJson("https://api.notion.com/v1/oauth/token", {
    method: "POST",
    headers: {
      authorization: `Basic ${Buffer.from(`${notion.clientId}:${notion.clientSecret}`).toString("base64")}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({
      grant_type: "authorization_code",
      code,
      redirect_uri: redirectUri
    })
  }, "Notion OAuth token exchange");
  return payload;
}

async function verifyGoogleAccess(accessToken) {
  if (!accessToken) throw new Error("Google OAuth did not return an access token to verify.");
  const payload = await fetchJson(`https://oauth2.googleapis.com/tokeninfo?${new URLSearchParams({ access_token: accessToken })}`, {}, "Google OAuth verification");
  const granted = new Set(String(payload.scope ?? "").split(/\s+/).filter(Boolean));
  const missing = GOOGLE_SCOPES.filter((scope) => !granted.has(scope));
  if (missing.length) throw new Error(`Google OAuth missing required scopes: ${missing.join(", ")}`);
  return payload;
}

async function verifySlackAccess(token) {
  if (!token) throw new Error("Slack OAuth did not return a token to verify.");
  const payload = await fetchJson("https://slack.com/api/auth.test", {
    headers: { authorization: `Bearer ${token}` }
  }, "Slack OAuth verification");
  if (!payload.ok) throw new Error(`Slack OAuth verification failed: ${payload.error ?? "unknown_error"}`);
  return payload;
}

async function verifyNotionAccess(token) {
  if (!token) throw new Error("Notion OAuth did not return a token to verify.");
  const payload = await fetchJson("https://api.notion.com/v1/users/me", {
    headers: {
      authorization: `Bearer ${token}`,
      "notion-version": NOTION_VERSION
    }
  }, "Notion OAuth verification");
  return payload;
}

async function savePendingState(pending, env) {
  const state = crypto.randomUUID();
  const directory = path.join(secretDir(env), "oauth-state");
  await fs.mkdir(directory, { recursive: true, mode: 0o700 });
  await fs.writeFile(path.join(directory, `${state}.json`), `${JSON.stringify(pending, null, 2)}\n`, { mode: 0o600 });
  return state;
}

async function readPendingState(state, env) {
  if (!state) throw new Error("OAuth callback is missing state.");
  const file = path.join(secretDir(env), "oauth-state", `${state}.json`);
  const pending = JSON.parse(await fs.readFile(file, "utf8"));
  await fs.rm(file, { force: true });
  if (Date.now() - Number(pending.createdAt ?? 0) > STATE_TTL_MS) throw new Error("OAuth approval link expired. Open /connect again.");
  return pending;
}

function bridgeOrigin(request, url) {
  const host = request.headers.host ?? url.host;
  return `http://${host}`;
}

function requireConnectKeys(provider, values) {
  const missing = Object.entries(values).filter(([, value]) => !value).map(([key]) => key);
  if (missing.length) throw new Error(`${provider} OAuth is not configured on this Nexus server.`);
}

function setupInstructions(provider, origin) {
  if (provider === "google") {
    return {
      redirectUri: `${origin}/oauth/callback`,
      adminConfig: "Google OAuth app configuration"
    };
  }
  if (provider === "slack") {
    return {
      redirectUri: `${origin}/oauth/callback`,
      adminConfig: "Slack OAuth app configuration",
      scopes: SLACK_READ_SCOPES
    };
  }
  return {
    redirectUri: `${origin}/oauth/callback`,
    adminConfig: "Notion OAuth app configuration",
    note: "Notion page creation also needs a selected parent page or database after authorization."
  };
}

function setupPage({ app, provider, origin, error }) {
  const setup = setupInstructions(provider, origin);
  return page(`${provider} connect setup`, `
    <h1>${escapeHtml(provider)} connection is not configured</h1>
    <p>${escapeHtml(error)}</p>
    <p>The Nexus server needs its ${escapeHtml(provider)} OAuth app configured before users can approve access.</p>
    <p>Required server config: <code>${escapeHtml(setup.adminConfig)}</code></p>
    <p>Registered redirect URI should be: <code>${escapeHtml(setup.redirectUri)}</code></p>
    ${setup.scopes ? `<p>Read-only Slack scopes: <code>${escapeHtml(setup.scopes.join(", "))}</code></p>` : ""}
    ${setup.note ? `<p>${escapeHtml(setup.note)}</p>` : ""}
    <p>Nexus app: <code>${escapeHtml(app)}</code></p>
  `);
}

function successPage(provider) {
  return page(`${provider} connected`, `
    <h1>${escapeHtml(provider)} connected</h1>
    <p>The token was saved locally for Nexus. You can close this tab.</p>
  `);
}

function failurePage(provider, error) {
  return page(`${provider} connect failed`, `
    <h1>${escapeHtml(provider)} connect failed</h1>
    <p>${escapeHtml(error)}</p>
    <p>Open <a href="/connect">/connect</a> to try again.</p>
  `);
}

function page(title, body) {
  return `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(title)}</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; max-width: 720px; margin: 48px auto; padding: 0 20px; line-height: 1.5; color: #151515; }
    code { background: #f2f2f2; border-radius: 6px; padding: 2px 6px; }
    a { color: #0b57d0; }
  </style>
</head>
<body>${body}</body>
</html>`;
}

async function fetchJson(url, options, label) {
  const response = await fetch(url, options);
  const text = await response.text();
  const payload = text ? JSON.parse(text) : {};
  if (!response.ok) throw new Error(`${label} failed with HTTP ${response.status}: ${text.slice(0, 400)}`);
  return payload;
}

function sendHtml(response, status, body) {
  response.writeHead(status, HTML_HEADERS);
  response.end(body);
}

function sendJson(response, status, body) {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(body));
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}
