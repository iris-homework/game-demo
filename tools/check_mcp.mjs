import { readFileSync, writeFileSync, mkdirSync, mkdtempSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const paths = JSON.parse(readFileSync(join(projectRoot, 'tools/local_paths.json'), 'utf8').replace(/^\uFEFF/, ''));
const requireMcp = createRequire(join(paths.mcpRoot, 'package.json'));
const { Client } = await import(pathToFileURL(requireMcp.resolve('@modelcontextprotocol/sdk/client/index.js')));
const { StdioClientTransport, getDefaultEnvironment } = await import(pathToFileURL(requireMcp.resolve('@modelcontextprotocol/sdk/client/stdio.js')));
const { ListToolsResultSchema, CallToolResultSchema } = await import(pathToFileURL(requireMcp.resolve('@modelcontextprotocol/sdk/types.js')));
const client = new Client({ name: 'midnight-tools-check', version: '1.0.0' }, { capabilities: {} });
const transport = new StdioClientTransport({
  command: paths.node,
  args: [join(paths.mcpRoot, 'node_modules/@coding-solo/godot-mcp/build/index.js')],
  env: { ...getDefaultEnvironment(), GODOT_PATH: paths.godot },
  stderr: 'inherit',
});
const call = async (name, args = {}) => {
  const result = await client.request({ method: 'tools/call', params: { name, arguments: args } }, CallToolResultSchema);
  if (result.isError) throw new Error(`${name}: ${JSON.stringify(result.content)}`);
  return result;
};
const textOf = (result) => result.content.filter((item) => item.type === 'text').map((item) => item.text).join('\n');
let running = false;
const deadline = setTimeout(() => { console.error('MCP verification timed out'); process.exit(1); }, 45000);
try {
  await client.connect(transport);
  const listed = await client.request({ method: 'tools/list', params: {} }, ListToolsResultSchema);
  const version = textOf(await call('get_godot_version'));
  const info = JSON.parse(textOf(await call('get_project_info', { projectPath: projectRoot })));
  // A separate project exercises run/debug/stop without loading the user's game or saves.
  const probe = mkdtempSync(join(tmpdir(), 'midnight-mcp-probe-'));
  writeFileSync(join(probe, 'project.godot'), 'config_version=5\n[application]\nconfig/name="Midnight MCP Probe"\nrun/main_scene="res://probe.tscn"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n');
  writeFileSync(join(probe, 'probe.gd'), 'extends Node\nfunc _ready() -> void:\n\tprint("MIDNIGHT_MCP_PROBE_READY")\n');
  writeFileSync(join(probe, 'probe.tscn'), '[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://probe.gd" id="1"]\n[node name="Probe" type="Node"]\nscript = ExtResource("1")\n');
  await call('run_project', { projectPath: probe });
  running = true;
  let output;
  for (let attempt = 0; attempt < 20; attempt++) {
    await new Promise((done) => setTimeout(done, 250));
    output = JSON.parse(textOf(await call('get_debug_output')));
    if (output.output.join('\n').includes('MIDNIGHT_MCP_PROBE_READY')) break;
  }
  if (!output.output.join('\n').includes('MIDNIGHT_MCP_PROBE_READY')) throw new Error('Godot probe did not start');
  if (output.errors.some((line) => /SCRIPT ERROR|Parse Error|^ERROR:/.test(line))) throw new Error('Godot probe reported errors');
  await call('stop_project');
  running = false;
  const report = { verifiedAt: new Date().toISOString(), godotVersion: version.trim(), project: info, tools: listed.tools.map((tool) => tool.name), runDebugStop: 'passed', probeProject: probe };
  const outputRoot = join(projectRoot, 'artifacts/qa');
  mkdirSync(outputRoot, { recursive: true });
  writeFileSync(join(outputRoot, 'mcp-check.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ godotVersion: report.godotVersion, toolCount: report.tools.length, tools: report.tools, runDebugStop: report.runDebugStop }, null, 2));
} finally {
  if (running) await call('stop_project').catch(() => {});
  await client.close();
  clearTimeout(deadline);
}
