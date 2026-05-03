/**
 * Ambient types for Cursor/VS Code’s built-in TypeScript checker.
 * Deploy still runs on Deno (see `deno.json`). For full Deno analysis, install
 * the Deno extension and enable it for `supabase/functions` only.
 */

declare module "jsr:@supabase/functions-js/edge-runtime.d.ts";

declare namespace Deno {
  namespace env {
    function get(key: string): string | undefined;
  }
  function serve(
    handler: (req: Request) => Response | Promise<Response>,
  ): void;
}

declare module "@supabase/supabase-js" {
  export interface User {
    id: string;
    email?: string;
    app_metadata?: Record<string, unknown>;
    user_metadata?: Record<string, unknown>;
  }

  export function createClient(
    supabaseUrl: string,
    supabaseKey: string,
    options?: Record<string, unknown>,
  ): any;
}
