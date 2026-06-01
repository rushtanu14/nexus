const SECTION_LABELS = [
  "Meeting title",
  "Title",
  "Date",
  "Context",
  "Resources",
  "Links",
  "Questions",
  "Open questions",
  "Due dates",
  "Due date",
  "Next meeting",
  "Next meeting date",
  "Follow-up meeting",
  "Follow up meeting",
  "Meeting minutes",
  "Minutes",
  "Notes",
  "Action items",
  "Actions",
  "Tasks",
  "Next steps",
  "Follow-up items",
  "Follow up items",
  "Follow-ups",
  "Today",
  "This week",
  "School",
  "Work",
  "Personal",
  "Errands"
];

const ACTION_PATTERN =
  /\b(i need to|i will|todo|to do|action item|follow up|complete|finish|submit|send|review|prepare|draft|schedule|email|ask|record|share|update|write|make|create|upload|approve|buy|call|text|pay|organize|clean|file|practice|study)\b/i;

export function createLifePlan(sourceText, { now = new Date(), homeDirectory = process.env.HOME ?? "~" } = {}) {
  const normalized = normalizePaste(sourceText);
  if (!normalized) throw new Error("life plan text is required");

  const title = titleFrom(normalized);
  const date = dateFrom(normalized, now);
  const context = contextFrom(normalized, title);
  const resources = parseResources(normalized);
  const questions = parseQuestions(normalized);
  const tasks = parseTasks(normalized);
  const nextMeeting = nextMeetingFrom(normalized, title);
  const brief = briefFrom({ title, context, tasks, questions, resources, nextMeeting });
  const automations = suggestedAutomations({ title, brief, tasks, questions, resources, nextMeeting, homeDirectory });
  const warnings = warningsFor({ tasks, resources, automations, nextMeeting });

  return {
    id: `life-plan-${now.getTime().toString(36)}`,
    title,
    date,
    context,
    brief,
    sourceText: normalized,
    stats: {
      tasks: tasks.length,
      resources: resources.length,
      questions: questions.length,
      automations: automations.length
    },
    tasks,
    resources,
    questions,
    nextMeeting,
    automations,
    warnings,
    rawSummary: rawSummary({ title, date, brief, tasks, questions, resources, nextMeeting })
  };
}

function normalizePaste(text) {
  return String(text ?? "")
    .normalize("NFKC")
    .replace(/\r\n?/g, "\n")
    .replace(/\u00a0/g, " ")
    .trim();
}

function cleanLine(line) {
  return String(line ?? "")
    .replace(/^[\s>]*(?:[-*]|\d+[.)]|[a-z][.)])\s*/i, "")
    .replace(/^\[[ xX]\]\s*/, "")
    .replace(/\s+/g, " ")
    .trim();
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function sectionPattern() {
  return SECTION_LABELS.map(escapeRegExp).join("|");
}

function extractSection(text, labels) {
  const labelPattern = labels.map(escapeRegExp).join("|");
  const match = text.match(
    new RegExp(
      `(?:^|\\n)\\s*(?:${labelPattern})\\s*(?::\\s*([^\\n]*))?\\s*(?:\\n|$)([\\s\\S]*?)(?=\\n\\s*(?:${sectionPattern()})\\s*(?::\\s*[^\\n]*)?\\s*(?:\\n|$)|$)`,
      "i"
    )
  );
  return [match?.[1] ?? "", match?.[2] ?? ""].join("\n").trim();
}

function isPlaceholderLine(line) {
  return /^(none|n\/a|na|no questions|no resources|no due dates|no action items|nothing yet)$/i.test(cleanLine(line));
}

function isSectionLabelLine(line) {
  const label = cleanLine(line).replace(/:$/, "").trim().toLowerCase();
  return SECTION_LABELS.some((sectionLabel) => sectionLabel.toLowerCase() === label);
}

function shortText(text, max = 120) {
  const trimmed = String(text ?? "").trim();
  if (trimmed.length <= max) return trimmed;
  return `${trimmed.slice(0, max - 1).trim()}...`;
}

function slugify(value, fallback = "life-plan") {
  return (
    String(value ?? "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "")
      .slice(0, 64) || fallback
  );
}

function unique(values) {
  return Array.from(new Set(values.map((value) => value.trim()).filter(Boolean)));
}

function createId(prefix, seed, index) {
  return `${prefix}-${slugify(seed, String(index + 1))}-${index + 1}`;
}

function monthDatePattern() {
  return /\b(?:monday,\s*|tuesday,\s*|wednesday,\s*|thursday,\s*|friday,\s*|saturday,\s*|sunday,\s*)?(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{1,2},\s+\d{4}\b/i;
}

function titleFrom(text) {
  const section = extractSection(text, ["Meeting title", "Title"]).split(/\n+/)[0]?.trim();
  if (section) return shortText(section, 72);
  const lines = text
    .split(/\n+/)
    .map(cleanLine)
    .filter((line) => line && !isSectionLabelLine(line) && !isDateLikeLine(line) && !isPlaceholderLine(line));
  const explicit = lines.find((line) => /\b(meeting|planning|checklist|dashboard|week|day|class|project)\b/i.test(line));
  return shortText(explicit || lines[0] || "Life command plan", 72);
}

function dateFrom(text, now) {
  const section = extractSection(text, ["Date"]).split(/\n+/)[0]?.trim();
  if (section) return section;
  const iso = text.match(/\b\d{4}-\d{2}-\d{2}\b/)?.[0];
  if (iso) return iso;
  const slashDate = text.match(/\b\d{1,2}\/\d{1,2}(?:\/\d{2,4})?\b/)?.[0];
  if (slashDate) return slashDate;
  const monthDate = text.match(monthDatePattern())?.[0].replace(/^(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday),\s*/i, "");
  return monthDate || now.toISOString().slice(0, 10);
}

function isDateLikeLine(line) {
  const cleaned = cleanLine(line);
  return /^\d{4}-\d{2}-\d{2}$/.test(cleaned) || /^\d{1,2}\/\d{1,2}(?:\/\d{2,4})?$/.test(cleaned) || monthDatePattern().test(cleaned);
}

function contextFrom(text, title) {
  const section = extractSection(text, ["Context"]);
  if (section) return shortText(section.replace(/\n+/g, " "), 220);
  const inferredTitle = title.toLowerCase();
  const line = text
    .split(/\n+/)
    .map(cleanLine)
    .find(
      (candidate) =>
        candidate.length > 28 &&
        candidate.toLowerCase() !== inferredTitle &&
        !isSectionLabelLine(candidate) &&
        !isDateLikeLine(candidate) &&
        !ACTION_PATTERN.test(candidate) &&
        !isQuestionCandidate(candidate)
    );
  return shortText(line || "Personal command center intake", 220);
}

function cleanUrl(url) {
  return url.replace(/[),.;:!?]+$/g, "");
}

function resourceType(url) {
  if (/youtube\.com|youtu\.be|vimeo\.com/i.test(url)) return "video";
  if (/docs\.google\.com\/presentation|slides/i.test(url)) return "slides";
  if (/docs\.google\.com|notion\.site|\.pdf(?:$|[?#])/i.test(url)) return "doc";
  return "link";
}

function defaultResourceTitle(url) {
  const type = resourceType(url);
  if (type === "video") return "Video";
  if (type === "slides") return "Slides";
  if (type === "doc") return "Document";
  return "Link";
}

function parseResources(text) {
  const resourceSection = extractSection(text, ["Resources", "Links"]);
  const resourceLines = resourceSection
    .split(/\n+/)
    .map(cleanLine)
    .filter((line) => line && !isPlaceholderLine(line));
  const urls = unique((`${resourceSection}\n${text}`.match(/https?:\/\/[^\s)]+/gi) ?? []).map(cleanUrl));
  return urls.slice(0, 10).map((url, index) => ({
    id: createId("resource", url, index),
    title: shortText(
      resourceLines
        .find((line) => line.includes(url) || line.includes(`${url}.`))
        ?.replace(url, "")
        .replace(cleanUrl(url), "")
        .replace(/^\s*(resource|link)\s*[:.-]\s*/i, "")
        .replace(/[.,;:!?]+$/g, "")
        .replace(/\s*[:-]\s*$/g, "")
        .trim() || defaultResourceTitle(url),
      72
    ),
    url,
    type: resourceType(url)
  }));
}

function removeUrls(line) {
  return cleanLine(line).replace(/https?:\/\/[^\s)]+/gi, "").trim();
}

function questionTextOutsideUrls(line) {
  return removeUrls(line).replace(/^(question|q)\s*[:.-]\s*/i, "").trim();
}

function isQuestionCandidate(line) {
  const questionText = questionTextOutsideUrls(line);
  return (questionText.includes("?") || /^(question|q)\b/i.test(removeUrls(line))) && /[a-z0-9]/i.test(questionText);
}

function parseQuestions(text) {
  const questionSection = extractSection(text, ["Questions", "Open questions"])
    .split(/\n+/)
    .map(cleanLine)
    .filter((line) => line && !isPlaceholderLine(line))
    .map((line) => line.replace(/^(question|q)\s*[:.-]\s*/i, "").trim());
  const source = `${extractSection(text, ["Meeting minutes", "Minutes", "Notes"])}\n${text}`;
  return unique([
    ...questionSection,
    ...source
      .split(/\n+/)
      .map(cleanLine)
      .filter(isQuestionCandidate)
      .map((line) => line.replace(/^(question|q)\s*[:.-]\s*/i, "").trim())
  ])
    .slice(0, 8)
    .map((question, index) => ({ id: createId("question", question, index), text: question }));
}

function dueDateTextFromLine(line) {
  const cleaned = cleanLine(line);
  return (
    cleaned.match(/\b(?:due|by|before)\s+([^.;:,\n]+)/i)?.[1]?.trim() ??
    cleaned.match(/\bon\s+(today|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday|next week|\d{1,2}\/\d{1,2}(?:\/\d{2,4})?|\d{4}-\d{2}-\d{2})\b/i)?.[1]?.trim() ??
    cleaned.match(/^(today|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday|next week)\b/i)?.[1]?.trim() ??
    cleaned.match(/\b(today|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday|next week)\b/i)?.[1]?.trim() ??
    ""
  );
}

function taskTitleFromLine(line) {
  return shortText(
    cleanLine(line)
      .replace(/^(todo|to do|action item|my task)\s*[:.-]\s*/i, "")
      .replace(/^i need to\s+/i, "")
      .replace(/^i will\s+/i, "")
      .replace(/\b(?:due|by|before)\s+([^.;:,\n]+)/i, "")
      .replace(/\bon\s+(today|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday|next week|\d{1,2}\/\d{1,2}(?:\/\d{2,4})?|\d{4}-\d{2}-\d{2})\b/i, "")
      .replace(/\s+\b(today|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday|next week)\b\.?$/i, "")
      .replace(/[.;:,]\s*$/g, "")
      .trim(),
    120
  );
}

function parseTasks(text) {
  const dueLines = extractSection(text, ["Due dates", "Due date"])
    .split(/\n+/)
    .map(cleanLine)
    .filter((line) => line && !isPlaceholderLine(line));
  const actionLines = extractSection(text, ["Action items", "Actions", "Tasks", "Next steps", "Follow-up items", "Follow up items", "Follow-ups", "Today", "This week", "School", "Work", "Personal", "Errands"])
    .split(/\n+/)
    .map(cleanLine)
    .filter((line) => line && !isPlaceholderLine(line));
  const notes = extractSection(text, ["Meeting minutes", "Minutes", "Notes"]) || text;
  const inferredLines = notes
    .split(/\n+/)
    .map(cleanLine)
    .filter((line) => ACTION_PATTERN.test(line));
  const sourceLines = unique([...actionLines, ...inferredLines, ...dueLines])
    .filter((line) => !isSectionLabelLine(line) && !isQuestionCandidate(line) && !isCalendarOnlyLine(line))
    .slice(0, 12);

  const tasks = [];
  const seen = new Set();
  for (const line of sourceLines) {
    const title = taskTitleFromLine(line);
    if (!title || isSectionLabelLine(title)) continue;
    const dueDateText = dueDateTextFromLine(line);
    const key = `${title.toLowerCase()}|${dueDateText.toLowerCase()}`;
    if (seen.has(key)) continue;
    seen.add(key);
    tasks.push({
      id: createId("task", line, tasks.length),
      title,
      status: "todo",
      dueDateText,
      priority: priorityFor(line, dueDateText),
      source: line
    });
  }

  return tasks.length
    ? tasks
    : [
        {
          id: "task-review-brief-1",
          title: "Review the assistant brief",
          status: "todo",
          dueDateText: "",
          priority: "normal",
          source: "Fallback personal follow-up"
        }
      ];
}

function isCalendarOnlyLine(line) {
  const cleaned = cleanLine(line);
  const hasActionCue = ACTION_PATTERN.test(cleaned) || /\b(due|by|before)\b/i.test(cleaned);
  const hasDateCue =
    isDateLikeLine(cleaned) ||
    monthDatePattern().test(cleaned) ||
    /\b(today|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday|next week)\b/i.test(cleaned);
  const hasTimeCue = /\b(?:at\s+)?\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)\b/i.test(cleaned);
  return !hasActionCue && hasDateCue && (hasTimeCue || cleaned.split(/\s+/).length <= 6);
}

function priorityFor(line, dueDateText) {
  if (/\b(urgent|asap|today|tonight|now|overdue)\b/i.test(`${line} ${dueDateText}`)) return "high";
  if (/\b(tomorrow|next week|soon)\b/i.test(`${line} ${dueDateText}`)) return "medium";
  return "normal";
}

function nextMeetingFrom(text, title) {
  const section = extractSection(text, ["Next meeting", "Next meeting date", "Follow-up meeting", "Follow up meeting"])
    .split(/\n+/)
    .map(cleanLine)
    .filter((line) => line && !isPlaceholderLine(line));
  const mentioned = text
    .split(/\n+/)
    .map(cleanLine)
    .filter((line) => /\b(next meeting|next call|follow[- ]?up meeting|meet again|schedule(?:d)?(?: our| the)? next)\b/i.test(line));
  const source = unique([...section, ...mentioned])[0];
  if (!source) return null;
  return {
    id: "next-meeting-1",
    title: `Next: ${title}`,
    dateText: nextMeetingDateTextFromLine(source) || "Date to confirm",
    timeText: nextMeetingTimeTextFromLine(source) || "Time to confirm",
    source
  };
}

function nextMeetingDateTextFromLine(line) {
  const cleaned = cleanLine(line);
  const monthDate = cleaned.match(monthDatePattern())?.[0].replace(/^(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday),\s*/i, "");
  if (monthDate) return monthDate;
  const iso = cleaned.match(/\b\d{4}-\d{2}-\d{2}\b/)?.[0];
  if (iso) return iso;
  const slashDate = cleaned.match(/\b\d{1,2}\/\d{1,2}(?:\/\d{2,4})?\b/)?.[0];
  if (slashDate) return slashDate;
  return cleaned.match(/\b(today|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday|next week)\b/i)?.[1] ?? "";
}

function nextMeetingTimeTextFromLine(line) {
  const cleaned = cleanLine(line);
  const range = cleaned.match(/\b(\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?))(?:\s*(?:-|to)\s*(\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)))?\b/i);
  if (!range) return "";
  const start = normalizeTimeText(range[1]);
  const end = range[2] ? normalizeTimeText(range[2]) : "";
  return end ? `${start} - ${end}` : start;
}

function normalizeTimeText(token) {
  return token
    .replace(/\s+/g, " ")
    .replace(/\ba\.?m\.?\b/i, "AM")
    .replace(/\bp\.?m\.?\b/i, "PM")
    .replace(/(\d)(AM|PM)$/i, "$1 $2")
    .trim()
    .toUpperCase();
}

function briefFrom({ title, context, tasks, questions, resources, nextMeeting }) {
  const topTasks = tasks
    .slice(0, 3)
    .map((task) => task.title)
    .join("; ");
  const blockers = questions.length ? `${questions.length} open question(s) need answers.` : "No open questions were detected.";
  const resourceText = resources.length ? `${resources.length} resource(s) are ready for follow-up.` : "No resource links were detected.";
  const meetingText = nextMeeting ? `Next meeting: ${nextMeeting.dateText} ${nextMeeting.timeText}.` : "No next meeting was detected.";
  return shortText(`${title}: ${context}. Priority follow-up: ${topTasks}. ${blockers} ${resourceText} ${meetingText}`, 520);
}

function suggestedAutomations({ title, brief, tasks, questions, resources, nextMeeting, homeDirectory }) {
  const safeSlug = slugify(title);
  const briefPath = `${homeDirectory}/Documents/Nexus/${safeSlug}-brief.md`;
  const checklist = formatChecklist({ title, brief, tasks, questions, resources, nextMeeting });
  const automations = [
    {
      id: "automation-save-brief",
      title: "Save command brief",
      intent: `write a string to ${briefPath} with content ${JSON.stringify(checklist)}`,
      impact: "Creates a local Markdown command brief with tasks, questions, resources, and next meeting details.",
      riskLevel: "low",
      requiresApproval: true
    }
  ];

  if (resources[0]) {
    automations.push({
      id: "automation-open-resource",
      title: "Open first resource",
      intent: `open ${resources[0].url} and extract the page title`,
      impact: `Opens ${resources[0].url} so Nexus can verify the reference before follow-up.`,
      riskLevel: "medium",
      requiresApproval: true
    });
  }

  if (nextMeeting) {
    automations.push({
      id: "automation-calendar-draft",
      title: "Draft calendar handoff",
      intent: `open https://calendar.google.com/calendar/render?action=TEMPLATE and prepare a calendar draft for ${nextMeeting.title}`,
      impact: "Opens Google Calendar with the meeting context ready for manual review.",
      riskLevel: "medium",
      requiresApproval: true
    });
  }

  return automations.slice(0, 4);
}

function formatChecklist({ title, brief, tasks, questions, resources, nextMeeting }) {
  return [
    `# ${title}`,
    "",
    brief,
    "",
    "## Tasks",
    ...tasks.map((task) => `- [ ] ${task.title}${task.dueDateText ? ` (due ${task.dueDateText})` : ""}`),
    "",
    "## Questions",
    ...(questions.length ? questions.map((question) => `- ${question.text}`) : ["- No open questions detected."]),
    "",
    "## Resources",
    ...(resources.length ? resources.map((resource) => `- ${resource.title}: ${resource.url}`) : ["- No resource links detected."]),
    "",
    "## Next Meeting",
    nextMeeting ? `- ${nextMeeting.dateText} ${nextMeeting.timeText}: ${nextMeeting.source}` : "- No next meeting detected."
  ].join("\n");
}

function warningsFor({ tasks, resources, automations, nextMeeting }) {
  const warnings = ["Nexus will not execute these automations until you generate a workflow, dry run it, and approve the exact version."];
  if (tasks.some((task) => task.priority === "high")) warnings.push("High-priority tasks were detected; review due dates before trusting an automation.");
  if (resources.length) warnings.push("Resource automations can open browser pages and should be reviewed before running.");
  if (nextMeeting) warnings.push("Calendar handoff is a draft only; review it before creating an event.");
  if (automations.some((automation) => automation.intent.includes("/Documents/Nexus/"))) warnings.push("The command brief automation writes a local file under Documents/Nexus.");
  return warnings;
}

function rawSummary({ title, date, brief, tasks, questions, resources, nextMeeting }) {
  return [
    `${title} (${date})`,
    "",
    brief,
    "",
    `Tasks: ${tasks.length}`,
    `Questions: ${questions.length}`,
    `Resources: ${resources.length}`,
    `Next meeting: ${nextMeeting ? `${nextMeeting.dateText} ${nextMeeting.timeText}` : "none"}`
  ].join("\n");
}
