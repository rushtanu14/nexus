import fs from "node:fs/promises";
import path from "node:path";

export const GOOGLE_SCOPES = [
  "https://www.googleapis.com/auth/gmail.compose",
  "https://www.googleapis.com/auth/calendar.events",
  "https://www.googleapis.com/auth/documents"
];

export const SLACK_READ_SCOPES = [
  "channels:read",
  "groups:read",
  "search:read"
];

const PROVIDER_FILES = {
  google: "google.json",
  slack: "slack.json",
  notion: "notion.json"
};

export function secretDir(env = process.env) {
  return path.resolve(env.NEXUS_MCP_SECRET_DIR ?? ".nexus-data/mcp-secrets");
}

export async function loadMcpSecrets(env = process.env) {
  const dir = secretDir(env);
  const [googleFile, slackFile, notionFile] = await Promise.all([
    readSecretFile(dir, "google"),
    readSecretFile(dir, "slack"),
    readSecretFile(dir, "notion")
  ]);
  return {
    google: {
      clientId: env.GOOGLE_CLIENT_ID ?? env.GMAIL_CLIENT_ID ?? googleFile.clientId ?? googleFile.client_id,
      clientSecret: env.GOOGLE_CLIENT_SECRET ?? env.GMAIL_CLIENT_SECRET ?? googleFile.clientSecret ?? googleFile.client_secret,
      refreshToken: googleFile.refreshToken ?? googleFile.refresh_token,
      accessToken: googleFile.accessToken ?? googleFile.access_token,
      calendarId: env.GOOGLE_CALENDAR_ID ?? googleFile.calendarId ?? googleFile.calendar_id,
      calendarTimeZone: env.GOOGLE_CALENDAR_TIME_ZONE ?? googleFile.calendarTimeZone ?? googleFile.calendar_time_zone,
      verifiedAt: googleFile.verifiedAt ?? googleFile.verified_at
    },
    slack: {
      clientId: env.SLACK_CLIENT_ID ?? slackFile.clientId ?? slackFile.client_id,
      clientSecret: env.SLACK_CLIENT_SECRET ?? slackFile.clientSecret ?? slackFile.client_secret,
      userToken: slackFile.userToken ?? slackFile.user_token,
      botToken: slackFile.botToken ?? slackFile.bot_token,
      verifiedAt: slackFile.verifiedAt ?? slackFile.verified_at
    },
    notion: {
      clientId: env.NOTION_CLIENT_ID ?? notionFile.clientId ?? notionFile.client_id,
      clientSecret: env.NOTION_CLIENT_SECRET ?? notionFile.clientSecret ?? notionFile.client_secret,
      token: notionFile.token ?? notionFile.apiKey ?? notionFile.api_key,
      parentPageId: env.NOTION_PARENT_PAGE_ID ?? notionFile.parentPageId ?? notionFile.parent_page_id,
      databaseId: env.NOTION_DATABASE_ID ?? notionFile.databaseId ?? notionFile.database_id,
      titleProperty: env.NOTION_TITLE_PROPERTY ?? notionFile.titleProperty ?? notionFile.title_property,
      verifiedAt: notionFile.verifiedAt ?? notionFile.verified_at
    }
  };
}

export async function saveProviderSecrets(provider, values, env = process.env) {
  if (!PROVIDER_FILES[provider]) throw new Error(`Unknown MCP secret provider: ${provider}`);
  const dir = secretDir(env);
  const existing = await readSecretFile(dir, provider);
  const cleaned = {
    ...existing,
    ...Object.fromEntries(Object.entries(values).filter(([, value]) => value !== undefined && value !== ""))
  };
  await fs.mkdir(dir, { recursive: true, mode: 0o700 });
  await fs.writeFile(path.join(dir, PROVIDER_FILES[provider]), `${JSON.stringify(cleaned, null, 2)}\n`, { mode: 0o600 });
  return { provider, keys: Object.keys(cleaned), path: path.join(dir, PROVIDER_FILES[provider]) };
}

export async function deleteProviderSecrets(provider, env = process.env) {
  if (!PROVIDER_FILES[provider]) throw new Error(`Unknown MCP secret provider: ${provider}`);
  const file = path.join(secretDir(env), PROVIDER_FILES[provider]);
  await fs.rm(file, { force: true });
  return { provider, deleted: true };
}

export async function providerAuthStatus(env = process.env) {
  const secrets = await loadMcpSecrets(env);
  return {
    google: {
      ok: Boolean(secrets.google.accessToken || (secrets.google.clientId && secrets.google.clientSecret && secrets.google.refreshToken)),
      connected: Boolean(secrets.google.verifiedAt),
      verifiedAt: secrets.google.verifiedAt,
      connectReady: Boolean(secrets.google.clientId && secrets.google.clientSecret),
      connectMissing: missingKeys({
        GOOGLE_CLIENT_ID: secrets.google.clientId,
        GOOGLE_CLIENT_SECRET: secrets.google.clientSecret
      }),
      missing: missingKeys({
        GOOGLE_CLIENT_ID: secrets.google.clientId,
        GOOGLE_CLIENT_SECRET: secrets.google.clientSecret,
        GOOGLE_REFRESH_TOKEN: secrets.google.refreshToken
      }, secrets.google.accessToken ? ["GOOGLE_ACCESS_TOKEN"] : [])
    },
    slack: {
      ok: Boolean(secrets.slack.userToken || secrets.slack.botToken),
      connected: Boolean(secrets.slack.verifiedAt),
      verifiedAt: secrets.slack.verifiedAt,
      connectReady: Boolean(secrets.slack.clientId && secrets.slack.clientSecret),
      connectMissing: missingKeys({
        SLACK_CLIENT_ID: secrets.slack.clientId,
        SLACK_CLIENT_SECRET: secrets.slack.clientSecret
      }),
      readOnly: true,
      missing: secrets.slack.userToken || secrets.slack.botToken ? [] : ["SLACK_USER_TOKEN or SLACK_BOT_TOKEN"]
    },
    notion: {
      ok: Boolean(secrets.notion.token && (secrets.notion.parentPageId || secrets.notion.databaseId)),
      connected: Boolean(secrets.notion.verifiedAt && (secrets.notion.parentPageId || secrets.notion.databaseId)),
      verifiedAt: secrets.notion.verifiedAt,
      connectReady: Boolean(secrets.notion.clientId && secrets.notion.clientSecret),
      connectMissing: missingKeys({
        NOTION_CLIENT_ID: secrets.notion.clientId,
        NOTION_CLIENT_SECRET: secrets.notion.clientSecret
      }),
      missing: [
        ...(secrets.notion.token ? [] : ["NOTION_TOKEN"]),
        ...(secrets.notion.parentPageId || secrets.notion.databaseId ? [] : ["NOTION_PARENT_PAGE_ID or NOTION_DATABASE_ID"])
      ]
    }
  };
}

export function redactedStatus(status) {
  return Object.fromEntries(Object.entries(status).map(([provider, item]) => [provider, {
    ok: item.ok,
    connected: item.connected,
    verifiedAt: item.verifiedAt,
    readOnly: item.readOnly,
    connectReady: item.connectReady,
    connectMissing: item.connectMissing,
    missing: item.missing
  }]));
}

async function readSecretFile(dir, provider) {
  try {
    const text = await fs.readFile(path.join(dir, PROVIDER_FILES[provider]), "utf8");
    return JSON.parse(text);
  } catch (error) {
    if (error.code === "ENOENT") return {};
    throw new Error(`Could not read ${provider} MCP secrets: ${error.message}`);
  }
}

function missingKeys(values, alternates = []) {
  if (alternates.length > 0) return [];
  return Object.entries(values).filter(([, value]) => !value).map(([key]) => key);
}
