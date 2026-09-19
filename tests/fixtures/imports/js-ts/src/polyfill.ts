// Side-effect-only module: imported for what it does, not for what it exports.
const g = globalThis as unknown as { __APP_VERSION__?: string };
g.__APP_VERSION__ ??= "2.0.0";

export {};
