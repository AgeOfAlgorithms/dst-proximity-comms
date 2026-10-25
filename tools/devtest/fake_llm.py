"""Dev only: a fake large language model for the agents' in-game test (tools/devtest, SCENE=agents) - an OpenAI-style
chat completions server on 127.0.0.1 that Koetama (--llm-model fake --llm-url http://127.0.0.1:<port>) asks for the
test's agent. A line with "follow" in it: words and a call to follow (the player who said it); after a tool result: a
follow-up; anything else: a short answer. Every request is printed (one JSON per line) for the test's log.

    python tools/devtest/fake_llm.py <port>
"""
import http.server
import json
import re
import sys


class Fake(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))) or b'{}')
        msgs = body.get('messages', [])
        last = msgs[-1] if msgs else {}
        print(json.dumps({'last': last, 'tools': [t.get('function', {}).get('name') for t in body.get('tools', [])]}), flush=True)
        if last.get('role') == 'tool':
            out = {'content': 'Oink! Pigman follows.'}
        else:
            text = str(last.get('content', ''))
            m = re.search(r'([^\n:]+): [^\n]*follow', text, re.I)
            if m:
                out = {'content': 'Oink oink! Lead the way, ' + m.group(1).strip() + '.',
                       'tool_calls': [{'id': 'call_follow', 'type': 'function',
                                       'function': {'name': 'follow', 'arguments': json.dumps({'player': m.group(1).strip()})}}]}
            else:
                out = {'content': 'Oink?'}
        data = json.dumps({'choices': [{'message': out, 'finish_reason': 'stop'}],
                           'usage': {'prompt_tokens': 120, 'completion_tokens': 12}}).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *a):
        pass


if __name__ == '__main__':
    http.server.ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1])), Fake).serve_forever()
