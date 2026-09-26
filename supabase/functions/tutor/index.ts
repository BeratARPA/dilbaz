import { verifyUser } from "../_shared/auth.ts";
import { createTutorHandler } from "./handler.ts";

Deno.serve(createTutorHandler({ verifyUser }));
