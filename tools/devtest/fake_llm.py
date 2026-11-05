"""Dev only: a fake large language model for the agents' in-game test (tools/devtest, SCENE=agents) - an OpenAI-style
chat completions server on 127.0.0.1 that Koetama (--llm-model fake --llm-url http://127.0.0.1:<port>) asks for the
test's agent. A line with "follow" in it: words and a call to follow (the player who said it); after a tool result: a
follow-up; "dance": a call to emote and "attack the <thing>": a call to attack (the Chatty Slime's, tools/devtest
in its repo); anything else: a short answer. Koetama's score question (an agent with criteria, Koetama 0.5.14): every
criterion 0.1, but "topic" 0.95 when the lines name the agent (0.2 when not) - or 0.05 when they say "ignore me" (a
skipped turn). Every request is printed
(one JSON per line) for the test's log.

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
        q = re.search(r'every name once: ([a-z0-9_=. ]+)\]', str(last.get('content', '')))
        if q:
            content = str(last.get('content', ''))
            said = content.split('[Koetama asks this')[0]
            ignore = re.search(r'ignore me', said, re.I)
            # (as a real model would: the topic only when the lines name this agent - "- topic: <Name> (...)" - so two
            #  creatures near one line don't both answer it; no name found: the topic)
            who = re.search(r'- topic: (.+?) (?:\(|is the topic)', content)
            mine = who is None or who.group(1).strip().lower() in said.split('\n', 1)[-1].lower()
            names = [x.split('=')[0] for x in q.group(1).split()]
            vals = {n: (0.05 if ignore else (0.95 if mine else 0.2)) if n == 'topic' else 0.1 for n in names}
            out = {'content': ' '.join('%s=%s' % (n, vals[n]) for n in names)}
        elif last.get('role') == 'tool':
            out = {'content': 'Oink! Pigman follows.'}
        else:
            text = str(last.get('content', ''))
            m = re.search(r'([^\n:]+): [^\n]*follow', text, re.I)
            d = re.search(r'([^\n:]+): [^\n]*danc', text, re.I)
            k = re.search(r'([^\n:]+): [^\n]*attack the (\w+)', text, re.I)
            if k:
                out = {'content': 'Grr! Blub!',
                       'tool_calls': [{'id': 'call_attack', 'type': 'function',
                                       'function': {'name': 'attack', 'arguments': json.dumps({'target': k.group(2)})}}]}
            elif d:
                out = {'content': 'Blub! Watch me dance!',
                       'tool_calls': [{'id': 'call_dance', 'type': 'function',
                                       'function': {'name': 'emote', 'arguments': json.dumps({'feeling': 'dance'})}}]}
            elif m:
                out = {'content': 'Oink oink! Lead the way, ' + m.group(1).strip() + '.',
                       'tool_calls': [{'id': 'call_follow', 'type': 'function',
                                       'function': {'name': 'follow', 'arguments': json.dumps({'player': m.group(1).strip()})}}]}
            else:
                out = {'content': 'Oink?'}
        if body.get('stream'):
            # (a streaming agent - Proximity Comms' default: Koetama asks for server-sent events; the words, then each
            #  tool call whole, then the end and the usage)
            chunks = []
            if out.get('content'):
                chunks.append({'choices': [{'index': 0, 'delta': {'role': 'assistant', 'content': out['content']}}]})
            for i, tc in enumerate(out.get('tool_calls', [])):
                chunks.append({'choices': [{'index': 0, 'delta': {'tool_calls': [dict(tc, index=i)]}}]})
            chunks.append({'choices': [{'index': 0, 'delta': {},
                                        'finish_reason': 'tool_calls' if out.get('tool_calls') else 'stop'}]})
            chunks.append({'choices': [], 'usage': {'prompt_tokens': 120, 'completion_tokens': 12}})
            data = ''.join('data: %s\n\n' % json.dumps(c) for c in chunks).encode() + b'data: [DONE]\n\n'
            self.send_response(200)
            self.send_header('Content-Type', 'text/event-stream')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
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
