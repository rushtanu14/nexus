import { RUNNERS } from "./runners/index.js";
import { validateNode } from "./node-schema.js";

export async function executeNode(node, context = {}) {
  try {
    validateNode(node);
  } catch (error) {
    return { error: error.message, failed_step: null };
  }

  const fields = Object.fromEntries(node.fields.map((field) => [field.id, field.value]));
  const steps = [];

  for (let index = 0; index < node.runner.steps.length; index += 1) {
    const step = node.runner.steps[index];
    try {
      const scope = { fields, context, steps, ...context };
      const args = resolveValue(step.args, scope);
      const output = await RUNNERS[step.primitive](args);
      steps.push({ output });
    } catch (error) {
      return { error: error.message, failed_step: index };
    }
  }

  const output = steps.at(-1)?.output;
  const result = { output };
  if (node.runner.output_binding) {
    const bindingName = resolveValue(node.runner.output_binding, { fields, context, steps, ...context });
    if (typeof bindingName === "string" && bindingName) result[bindingName] = output;
  }
  return result;
}

export function resolveValue(value, scope) {
  if (Array.isArray(value)) return value.map((item) => resolveValue(item, scope));
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, resolveValue(item, scope)]));
  }
  if (typeof value !== "string") return value;

  const exact = value.match(/^\{\{\s*([^{}]+?)\s*\}\}$/);
  if (exact) return resolveReference(exact[1], scope);
  return value.replace(/\{\{\s*([^{}]+?)\s*\}\}/g, (_, reference) => {
    const resolved = resolveReference(reference, scope);
    return typeof resolved === "string" ? resolved : JSON.stringify(resolved);
  });
}

function resolveReference(reference, scope) {
  if (reference === "steps.last.output") return scope.steps.at(-1)?.output;
  const resolved = reference.split(".").reduce((current, key) => current?.[key], scope);
  if (resolved === undefined) throw new Error(`unresolved binding: ${reference}`);
  if (typeof resolved === "string" && resolved.includes("{{")) return resolveValue(resolved, scope);
  return resolved;
}
