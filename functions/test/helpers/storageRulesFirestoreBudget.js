"use strict";

/**
 * Static budget check for Cloud Storage Security Rules cross-service reads.
 *
 * Production Storage Rules may access at most TWO distinct Cloud Firestore
 * documents per evaluation (firestore.get / firestore.exists); a third
 * distinct document is a permission-denied error. Repeated access to the same
 * document is cached and counted once. The Storage emulator does NOT enforce
 * this limit, so an emulator test cannot catch a violation. See
 * https://firebase.google.com/docs/storage/security/rules-conditions
 * ("No more than two Firestore documents may be accessed in a single Rules
 * evaluation") and https://firebase.google.com/docs/rules/rules-behavior.
 *
 * This helper expands every `allow` expression by inlining user-defined
 * functions (substituting arguments for parameters) and `let` bindings, then
 * collects the distinct Firestore document path expressions it can reach.
 * It ignores short-circuiting, so the count is a conservative upper bound.
 */

function stripComments(source) {
  return source
    .split("\n")
    .map((line) => {
      let inString = null;
      for (let i = 0; i < line.length; i += 1) {
        const ch = line[i];
        if (inString) {
          if (ch === "\\") i += 1;
          else if (ch === inString) inString = null;
        } else if (ch === "\"" || ch === "'") {
          inString = ch;
        } else if (ch === "/" && line[i + 1] === "/") {
          return line.slice(0, i);
        }
      }
      return line;
    })
    .join("\n");
}

function matchClosing(text, openIndex, open, close) {
  let depth = 0;
  let inString = null;
  for (let i = openIndex; i < text.length; i += 1) {
    const ch = text[i];
    if (inString) {
      if (ch === "\\") i += 1;
      else if (ch === inString) inString = null;
      continue;
    }
    if (ch === "\"" || ch === "'") inString = ch;
    else if (ch === open) depth += 1;
    else if (ch === close) {
      depth -= 1;
      if (depth === 0) return i;
    }
  }
  throw new Error(`Unbalanced ${open}${close} at ${openIndex}`);
}

function splitTopLevel(text, separator) {
  const parts = [];
  let depth = 0;
  let inString = null;
  let start = 0;
  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];
    if (inString) {
      if (ch === "\\") i += 1;
      else if (ch === inString) inString = null;
      continue;
    }
    if (ch === "\"" || ch === "'") inString = ch;
    else if ("([{".includes(ch)) depth += 1;
    else if (")]}".includes(ch)) depth -= 1;
    else if (ch === separator && depth === 0) {
      parts.push(text.slice(start, i));
      start = i + 1;
    }
  }
  parts.push(text.slice(start));
  return parts.map((part) => part.trim()).filter((part) => part.length > 0);
}

function replaceIdentifier(text, name, replacement) {
  const pattern = new RegExp(`(?<![.\\w$])${name}(?![\\w$])`, "g");
  return text.replace(pattern, () => replacement);
}

function parseFunctions(source) {
  const functions = new Map();
  const pattern = /function\s+(\w+)\s*\(([^)]*)\)\s*\{/g;
  let match;
  while ((match = pattern.exec(source)) !== null) {
    const open = match.index + match[0].length - 1;
    const close = matchClosing(source, open, "{", "}");
    const body = source.slice(open + 1, close);
    const statements = splitTopLevel(body, ";");
    let returned = null;
    const lets = [];
    for (const statement of statements) {
      const letMatch = /^let\s+(\w+)\s*=\s*([\s\S]+)$/.exec(statement);
      if (letMatch) lets.push([letMatch[1], letMatch[2]]);
      else if (statement.startsWith("return")) returned = statement.slice("return".length).trim();
    }
    if (returned === null) throw new Error(`function ${match[1]} has no return`);
    // Substitute the last binding first: its expression may reference earlier
    // bindings, which are then substituted in turn.
    for (let i = lets.length - 1; i >= 0; i -= 1) {
      returned = replaceIdentifier(returned, lets[i][0], `(${lets[i][1]})`);
    }
    const params = match[2].split(",").map((p) => p.trim()).filter(Boolean);
    functions.set(match[1], {params, body: returned});
  }
  return functions;
}

function expand(expression, functions, depth = 0) {
  if (depth > 40) throw new Error("Rules function expansion too deep");
  let result = "";
  let index = 0;
  const callPattern = /(?<![.\w$])(\w+)\s*\(/g;
  let match;
  while ((match = callPattern.exec(expression)) !== null) {
    const name = match[1];
    if (!functions.has(name)) continue;
    const open = match.index + match[0].length - 1;
    const close = matchClosing(expression, open, "(", ")");
    const args = splitTopLevel(expression.slice(open + 1, close), ",")
      .map((arg) => expand(arg, functions, depth + 1));
    const fn = functions.get(name);
    let body = fn.body;
    fn.params.forEach((param, i) => {
      body = replaceIdentifier(body, param, `(${args[i] ?? "undefined"})`);
    });
    result += expression.slice(index, match.index) + `(${expand(body, functions, depth + 1)})`;
    index = close + 1;
    callPattern.lastIndex = close + 1;
  }
  return result + expression.slice(index);
}

function firestoreDocumentPaths(expandedExpression) {
  const paths = new Set();
  const pattern = /firestore\.(get|exists)\s*\(/g;
  let match;
  while ((match = pattern.exec(expandedExpression)) !== null) {
    const open = match.index + match[0].length - 1;
    const close = matchClosing(expandedExpression, open, "(", ")");
    // Canonical form: argument substitution adds redundant parentheses, so
    // drop all parentheses, `$` and whitespace. Two paths that differ only in
    // grouping are the same document expression.
    paths.add(expandedExpression.slice(open + 1, close).replace(/[\s()$]/g, ""));
  }
  return paths;
}

/**
 * Returns one entry per `allow` statement: the enclosing match path, the
 * methods, and the distinct Firestore document path expressions it can reach.
 */
function analyzeStorageRules(source) {
  const clean = stripComments(source);
  const functions = parseFunctions(clean);
  const results = [];
  const matchStack = [];
  const tokenPattern = /match\s+(\S+)\s*\{|allow\s+([\w,\s]+?)\s*:\s*if\s+|\{|\}/g;
  let token;
  let braceStack = [];
  while ((token = tokenPattern.exec(clean)) !== null) {
    if (token[0].startsWith("match")) {
      matchStack.push(token[1]);
      braceStack.push("match");
    } else if (token[0].startsWith("allow")) {
      const start = token.index + token[0].length;
      let depth = 0;
      let end = start;
      for (; end < clean.length; end += 1) {
        const ch = clean[end];
        if ("([{".includes(ch)) depth += 1;
        else if (")]}".includes(ch)) depth -= 1;
        else if (ch === ";" && depth === 0) break;
      }
      const expression = clean.slice(start, end);
      const paths = firestoreDocumentPaths(expand(expression, functions));
      results.push({
        match: matchStack.join(""),
        methods: token[2].split(",").map((m) => m.trim()),
        paths: [...paths].sort(),
      });
      tokenPattern.lastIndex = end + 1;
    } else if (token[0] === "{") {
      braceStack.push("block");
    } else if (token[0] === "}") {
      const kind = braceStack.pop();
      if (kind === "match") matchStack.pop();
    }
  }
  return results;
}

module.exports = {
  STORAGE_RULES_FIRESTORE_DOCUMENT_LIMIT: 2,
  analyzeStorageRules,
};
