// Reached only by the /// <reference path="..."> in src/index.ts.
declare module "*.css";

declare module "clsx/lite" {
  const lite: (...args: unknown[]) => string;
  export default lite;
}

declare global {
  interface Window {
    __APP_VERSION__: string;
  }
}

export {};
