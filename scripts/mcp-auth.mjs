#!/usr/bin/env node
import { execFile } from "node:child_process";
import crypto from "node:crypto";
import http from "node:http";
import { promisify } from "node:util";
import {
  GOOGLE_SCOPES,
  loadMcpSecrets,
  providerAuthStatus,
  redactedStatus,
  saveProviderSecrets,
  secretDir
} from "./mcp-secret-store.mjs";

const execFileAsync = promisify(execFile);
const command = process.argv[2] ?? "status";

if (command === "status") {
  await printStatus();
} else if (command === "save-google") {
  await saveGoogleFromEnv();
  await printStatus();
} else if (command === "google-login") {
  await googleLogin();
  await printStatus();
} else if (command === "save-slack") {
  await saveSlackFromEnv();
  await printStatus();
} else if (command === "save-notion") {
  await saveNotionFromEnv();
  await printStatus();
} else if (command === "save-all") {
  await saveAllFromEnv();
  await printStatus();
} else {
  printHelp();
}

async function printStatus() {
  const status = await providerAuthStatus();
  console.log(JSON.stringify({
    secretDir: secretDir(),
    providers: redactedStatus(status)
  }, null, 2));
}

async function saveGoogleFromEnv() {
  const result = await saveProviderSecrets("google", {
    clientId: process.env.GOOGLE_CLIENT_ID ?? process.env.GMAIL_CLIENT_ID,
    clientSecret: process.env.GOOGLE_CLIENT_SECRET ?? process.env.GMAIL_CLIENT_SECRET,
    calendarId: process.env.GOOGLE_CALENDAR_ID,
    calendarTimeZone: process.env.GOOGLE_CALENDAR_TIME_ZONE
  });
  console.log(`saved google keys: ${result.keys.join(", ")}`);
}

async function saveSlackFromEnv() {
  const result = await saveProviderSecrets("slack", {
    clientId: process.env.SLACK_CLIENT_ID,
    clientSecret: process.env.SLACK_CLIENT_SECRET
  });
  console.log(`saved slack keys: ${result.keys.join(", ")}`);
}

async function saveNotionFromEnv() {
  const result = await saveProviderSecrets("notion", {
    clientId: process.env.NOTION_CLIENT_ID,
    clientSecret: process.env.NOTION_CLIENT_SECRET,
    parentPageId: process.env.NOTION_PARENT_PAGE_ID,
    databaseId: process.env.NOTION_DATABASE_ID,
    titleProperty: process.env.NOTION_TITLE_PROPERTY
  });
  console.log(`saved notion keys: ${result.keys.join(", ")}`);
}

async function saveAllFromEnv() {
  if (process.env.GOOGLE_CLIENT_ID || process.env.GMAIL_CLIENT_ID) await saveGoogleFromEnv();
  if (process.env.SLACK_CLIENT_ID) await saveSlackFromEnv();
  if (process.env.NOTION_CLIENT_ID) await saveNotionFromEnv();
}

async function googleLogin() {
  await saveGoogleFromEnv();
  const { google } = await loadMcpSecrets();
  if (!google.clientId || !google.clientSecret) {
    throw new Error("Run GOOGLE_CLIENT_ID=... GOOGLE_CLIENT_SECRET=... npm run mcp:auth -- save-google first.");
  }
  const port = Number(process.env.NEXUS_GOOGLE_AUTH_PORT ?? 9010);
  const redirectUri = `http://127.0.0.1:${port}/oauth/google/callback`;
  const state = crypto.randomUUID();
  const authUrl = googleAuthUrl({ clientId: google.clientId, redirectUri, state });
  const server = http.createServer();
  const codePromise = waitForGoogleCode(server, { state });
  await new Promise((resolve) => server.listen(port, "127.0.0.1", resolve));
  console.log(`Open this URL if the browser does not open automatically:\n${authUrl}`);
  try {
    await execFileAsync("open", [authUrl]);
  } catch {
    // The printed URL is enough for non-macOS shells.
  }
  const code = await codePromise;
  await new Promise((resolve) => server.close(resolve));
  const token = await exchangeGoogleCode({ code, clientId: google.clientId, clientSecret: google.clientSecret, redirectUri });
  if (!token.refresh_token) {
    throw new Error("Google did not return a refresh token. Re-run google-login and approve the consent screen, or remove the old app grant first.");
  }
  await saveProviderSecrets("google", {
    clientId: google.clientId,
    clientSecret: google.clientSecret,
    refreshToken: token.refresh_token,
    accessToken: token.access_token,
    calendarId: google.calendarId,
    calendarTimeZone: google.calendarTimeZone
  });
  console.log("saved google refresh token");
}

function googleAuthUrl({ clientId, redirectUri, state }) {
  const params = new URLSearchParams({
    client_id: clientId,
    redirect_uri: redirectUri,
    response_type: "code",
    access_type: "offline",
    prompt: "consent",
    state,
    scope: GOOGLE_SCOPES.join(" ")
  });
  return `https://accounts.google.com/o/oauth2/v2/auth?${params}`;
}

function waitForGoogleCode(server, { state }) {
  return new Promise((resolve, reject) => {
    server.on("request", (request, response) => {
      try {
        const url = new URL(request.url, "http://127.0.0.1");
        if (url.pathname !== "/oauth/google/callback") {
          response.writeHead(404).end("Not found");
          return;
        }
        if (url.searchParams.get("state") !== state) throw new Error("Google OAuth state mismatch.");
        const error = url.searchParams.get("error");
        if (error) throw new Error(`Google OAuth error: ${error}`);
        const code = url.searchParams.get("code");
        if (!code) throw new Error("Google OAuth callback did not include a code.");
        response.writeHead(200, { "content-type": "text/plain" }).end("Nexus Google auth saved. You can close this tab.");
        resolve(code);
      } catch (error) {
        response.writeHead(400, { "content-type": "text/plain" }).end(error.message);
        reject(error);
      }
    });
  });
}

async function exchangeGoogleCode({ code, clientId, clientSecret, redirectUri }) {
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: clientId,
      client_secret: clientSecret,
      redirect_uri: redirectUri,
      grant_type: "authorization_code"
    })
  });
  const text = await response.text();
  const payload = text ? JSON.parse(text) : {};
  if (!response.ok) throw new Error(`Google token exchange failed with HTTP ${response.status}: ${text.slice(0, 400)}`);
  return payload;
}

function printHelp() {
  console.log(`Usage:
  npm run mcp:auth -- status
  GOOGLE_CLIENT_ID=... GOOGLE_CLIENT_SECRET=... npm run mcp:auth -- save-google
  npm run mcp:auth -- google-login
  SLACK_CLIENT_ID=... SLACK_CLIENT_SECRET=... npm run mcp:auth -- save-slack
  NOTION_CLIENT_ID=... NOTION_CLIENT_SECRET=... npm run mcp:auth -- save-notion
  npm run mcp:auth -- save-all`);
}
