// 앱 도움말 챗봇 Edge Function. 로직은 handler.mjs(Node 테스트: tools/app_help_function.test.mjs).
// 필요한 서버 비밀값: GROQ_API_KEY (선택: GROQ_MODEL). 키는 클라이언트·로그·저장소에 넣지 않는다.
import kb from './help_kb.json' with { type: 'json' };
import { createHandler } from './handler.mjs';

Deno.serve(createHandler({ kb, env: (name: string) => Deno.env.get(name), fetch }));
