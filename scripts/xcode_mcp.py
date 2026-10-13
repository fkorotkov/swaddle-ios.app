#!/usr/bin/env python3
"""Call Xcode's native MCP bridge; batch related operations in one workspace session."""
import json
import pathlib
import select
import subprocess
import sys
import time

PROJECT = str(pathlib.Path(__file__).resolve().parents[1] / 'BabyActivityRecorder.xcodeproj')

def main():
    jobs = json.loads(pathlib.Path(sys.argv[2]).read_text()) if sys.argv[1] == '--batch' else [{'name': sys.argv[1], 'arguments': json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}}]
    process = subprocess.Popen(['xcrun', 'mcpbridge'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
    def call(request_id, method, params):
        process.stdin.write(json.dumps({'jsonrpc': '2.0', 'id': request_id, 'method': method, 'params': params}) + '\n')
        process.stdin.flush()
        deadline = time.monotonic() + 240
        while time.monotonic() < deadline:
            if not select.select([process.stdout], [], [], 1)[0]:
                continue
            line = process.stdout.readline()
            if not line:
                raise RuntimeError('Xcode MCP bridge closed')
            response = json.loads(line)
            if response.get('id') == request_id:
                return response.get('result', response)
        raise TimeoutError('Xcode MCP response timed out')
    try:
        call(1, 'initialize', {'protocolVersion': '2024-11-05', 'capabilities': {}, 'clientInfo': {'name': 'LittleLogBuilder', 'version': '1.0'}})
        process.stdin.write(json.dumps({'jsonrpc': '2.0', 'method': 'notifications/initialized'}) + '\n')
        process.stdin.flush()
        opened = call(2, 'tools/call', {'name': 'XcodeOpenWorkspace', 'arguments': {'path': PROJECT}})
        workspace = opened.get('structuredContent', {}).get('workspaceIdentifier')
        if not workspace:
            print(json.dumps(opened, indent=2)); return 1
        if any(j['name'] in ['BuildProject', 'RunProject', 'RunAllTests', 'RunSomeTests', 'RenderPreview'] for j in jobs):
            call(3, 'tools/call', {'name': 'XcodeSwitchScheme', 'arguments': {'schemeName': 'BabyActivityRecorder', 'workspaceIdentifier': workspace}})
            call(4, 'tools/call', {'name': 'XcodeSwitchRunDestination', 'arguments': {'displayTitle': 'iPhone 18 Pro', 'workspaceIdentifier': workspace}})
        for request_id, job in enumerate(jobs, 5):
            if job['name'] not in ['XcodeListTemplates', 'DocumentationSearch', 'XcodeListWorkspaces']:
                job.setdefault('arguments', {})['workspaceIdentifier'] = workspace
            result = call(request_id, 'tools/call', job)
            print(json.dumps({'tool': job['name'], 'result': result.get('structuredContent', result)}, indent=2), flush=True)
            if result.get('isError'):
                return 1
    finally:
        process.terminate()
    return 0

if __name__ == '__main__':
    sys.exit(main())
