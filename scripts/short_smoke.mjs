import assert from 'node:assert/strict';
import { execFileSync, spawn, spawnSync } from 'node:child_process';
import { mkdtemp, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import readline from 'node:readline';
import { setTimeout as sleep } from 'node:timers/promises';

const [engineArg, ffmpegArg] = process.argv.slice(2);
assert(engineArg && ffmpegArg, 'Usage: node scripts/short_smoke.mjs ENGINE_EXE FFMPEG_EXE');
const engine = path.resolve(engineArg);
const ffmpeg = path.resolve(ffmpegArg);
const workspace = await mkdtemp(path.join(tmpdir(), 'clippify-short-smoke-'));
const fixture = path.join(workspace, 'فيديو اختبار.mp4');
execFileSync(ffmpeg, [
  '-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=duration=3:size=640x360:rate=30',
  '-f', 'lavfi', '-i', 'sine=frequency=460:duration=3',
  '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', fixture,
]);
const pauseFixture = path.join(workspace, 'pause.mp4');
const silentFixture = path.join(workspace, 'silent.mp4');
execFileSync(ffmpeg, [
  '-v', 'error', '-f', 'lavfi', '-i', 'color=c=0x151d2c:s=360x640:r=30:d=3',
  '-c:v', 'libx264', '-pix_fmt', 'yuv420p', silentFixture,
]);
execFileSync(ffmpeg, [
  '-v', 'error', '-f', 'lavfi', '-i', 'color=c=red:s=360x202:r=30:d=7',
  '-f', 'lavfi', '-i', 'sine=frequency=440:duration=7',
  '-af', "volume=volume=0:enable='between(t,2,4)'",
  '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', pauseFixture,
]);

const env = { ...process.env, CLIPPIFY_FFMPEG: ffmpeg };
delete env.WHISPER_MODEL_PATH;
delete env.CLIPPIFY_SHORT_TEAMSOCLO_KEY;
delete env.CLIPPIFY_SHORT_TEAMSOCLO_MODEL;

async function checkVisionGate() {
  const gateEnv = {
    ...process.env,
    CLIPPIFY_FFMPEG: ffmpeg,
    CLIPPIFY_SHORT_TEAMSOCLO_KEY: 'fixture-key-that-must-not-be-used',
    CLIPPIFY_SHORT_TEAMSOCLO_MODEL: 'fixture-model',
    CLIPPIFY_SHORT_AI_BASE_URL: 'https://coarena.ai/api/v1',
  };
  delete gateEnv.CLIPPIFY_SHORT_AI_VISION;
  const gate = spawn(engine, ['serve', '--port', '0', '--local-short'], {
    cwd: workspace, env: gateEnv, windowsHide: true, stdio: ['ignore', 'pipe', 'inherit'],
  });
  const gateExit = new Promise((resolve) => gate.once('close', resolve));
  const gateTimeout = setTimeout(() => gate.kill(), 10_000);
  const lines = readline.createInterface({ input: gate.stdout });
  try {
    for await (const line of lines) {
      const { listening } = JSON.parse(line);
      const gateBase = `http://${listening}`;
      const response = await fetch(`${gateBase}/api/auto-edit`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          video_path: fixture,
          answers: { mode: 'short_auto', short_director: 'ai' },
        }),
        signal: AbortSignal.timeout(10_000),
      });
      assert.equal(response.status, 202);
      const { session_id: id } = await response.json();
      const started = Date.now();
      let state;
      do {
        await sleep(100);
        state = await (await fetch(`${gateBase}/api/auto-edit/status/${id}`, {
          signal: AbortSignal.timeout(5_000),
        })).json();
      } while (!['done', 'error'].includes(state.status) && Date.now() - started < 5_000);
      assert.equal(state.status, 'error', 'AI without image consent must not run');
      assert.match(state.error, /إذن إرسال صور/);
      assert.ok(Date.now() - started < 5_000, 'the gate must reject before analysis');
      return;
    }
    assert.fail('Vision gate engine exited before listening');
  } finally {
    clearTimeout(gateTimeout);
    lines.close();
    gate.kill();
    await gateExit;
  }
}
await checkVisionGate();
const worker = spawn(engine, ['serve', '--port', '0', '--local-short'], {
  cwd: workspace, env, windowsHide: true, stdio: ['ignore', 'pipe', 'inherit'],
});
const exit = new Promise((resolve) => worker.once('close', resolve));
const stdout = readline.createInterface({ input: worker.stdout });
const startupTimeout = setTimeout(() => worker.kill(), 10_000);
let verified = false;
try {
  for await (const line of stdout) {
    clearTimeout(startupTimeout);
    const { listening } = JSON.parse(line);
    assert.match(listening, /^127\.0\.0\.1:\d+$/);
    const base = `http://${listening}`;
    const request = (route, options) => fetch(base + route, {
      ...options, signal: AbortSignal.timeout(10_000),
    });
    const health = await request('/api/health');
    assert.equal((await health.json()).engine, 'rust');
    const unknownQuestions = await request('/api/auto-edit/questions/smoke-unknown', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ answers: [] }),
    });
    assert.equal(unknownQuestions.status, 404, 'questions need a live session');
    const response = await request('/api/auto-edit', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        video_path: fixture,
        answers: { mode: 'short_auto', platform: 'reels', clip_duration_sec: 30, n_clips: 1 },
      }),
    });
    assert.equal(response.status, 202);
    const { session_id: id } = await response.json();
    const socket = new WebSocket(`ws://${listening}/api/ws/progress/${id}`);
    const completed = new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        socket.close();
        reject(new Error('No terminal WebSocket event'));
      }, 75_000);
      socket.addEventListener('message', ({ data }) => {
        const event = JSON.parse(data);
        if (!['done', 'error'].includes(event.type)) return;
        clearTimeout(timeout);
        socket.close();
        resolve(event);
      });
      socket.addEventListener('error', () => {
        clearTimeout(timeout);
        reject(new Error('WebSocket disconnected'));
      }, { once: true });
    });
    completed.catch(() => {});
    const deadline = Date.now() + 75_000;
    let state;
    do {
      await sleep(250);
      state = await (await request(`/api/auto-edit/status/${id}`)).json();
    } while (!['done', 'error'].includes(state.status) && Date.now() < deadline);
    assert.equal(state.status, 'done', state.error);
    assert.equal(state.result.source, 'local_audio');
    assert.equal(state.result.clips.length, 1);
    assert.deepEqual((await completed).result.clips, state.result.clips);
    const output = await request(`/api/files/${state.result.clips[0].file_url}`);
    assert.equal(output.status, 200);
    const file = path.join(workspace, 'result.mp4');
    await writeFile(file, Buffer.from(await output.arrayBuffer()));
    const verification = spawnSync(ffmpeg, [
      '-v', 'info', '-xerror', '-i', file, '-f', 'null', '-',
    ], { encoding: 'utf8' });
    assert.equal(verification.status, 0, verification.stderr);
    assert.match(verification.stderr, /Video: h264[^\r\n]+1080x1920[^\r\n]+30 fps/);
    assert.match(verification.stderr, /Audio: aac/);
    const stylized = await request('/api/auto-edit', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        video_path: pauseFixture,
        answers: {
          mode: 'short_auto', clip_duration_sec: 30,
          edit_brief: 'ألوان دافية، زوم بطيء، تلاشي، قص الصمت',
          zoom_policy: 'request_only',
        },
      }),
    });
    assert.equal(stylized.status, 202);
    const { session_id: stylizedId } = await stylized.json();
    const styleDeadline = Date.now() + 75_000;
    let styled;
    do {
      await sleep(200);
      styled = await (await request(`/api/auto-edit/status/${stylizedId}`)).json();
    } while (!['done', 'error'].includes(styled.status) && Date.now() < styleDeadline);
    assert.equal(styled.status, 'done', styled.error);
    assert.equal(styled.result.edit_plan.grade, 'warm');
    assert.equal(styled.result.edit_plan.zoom, 'slow_push');
    assert.equal(styled.result.edit_plan.transition, 'fade');
    assert.equal(styled.result.provider_status, 'disabled');
    assert.equal(styled.result.cuts, 1);
    assert.ok(styled.result.clips[0].duration_sec < 6);
    const styledFile = path.join(workspace, 'styled.mp4');
    const styledOutput = await request(`/api/files/${styled.result.clips[0].file_url}`);
    assert.equal(styledOutput.status, 200);
    await writeFile(styledFile, Buffer.from(await styledOutput.arrayBuffer()));
    execFileSync(ffmpeg, ['-v', 'error', '-xerror', '-i', styledFile, '-f', 'null', '-']);
    const [red, green, blue] = execFileSync(ffmpeg, [
      '-v', 'error', '-ss', '2', '-i', styledFile, '-frames:v', '1',
      '-vf', 'crop=2:2:540:900,format=rgb24', '-threads:v', '1', '-f', 'rawvideo', '-',
    ]);
    assert.ok(red > 180 && green < 90 && blue < 90, `Warm grade lost a saturated red (${red}, ${green}, ${blue})`);
    const designed = await request('/api/auto-edit', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        video_path: silentFixture,
        answers: {
          mode: 'short_auto', creative_style: 'kinetic', creative_title: 'اختبار الإيقاع',
          creative_music: true, creative_effects: true,
        },
      }),
    });
    assert.equal(designed.status, 202);
    const { session_id: designedId } = await designed.json();
    let creative;
    const designDeadline = Date.now() + 75_000;
    do {
      await sleep(200);
      creative = await (await request(`/api/auto-edit/status/${designedId}`)).json();
    } while (!['done', 'error'].includes(creative.status) && Date.now() < designDeadline);
    assert.equal(creative.status, 'done', creative.error);
    assert.equal(creative.result.creative.title, 'اختبار الإيقاع');
    assert.equal(creative.result.creative.original_music, true);
    assert.equal(creative.result.clips[0].has_captions, false);
    const designFile = path.join(workspace, 'designed.mp4');
    const designOutput = await request(`/api/files/${creative.result.clips[0].file_url}`);
    assert.equal(designOutput.status, 200);
    await writeFile(designFile, Buffer.from(await designOutput.arrayBuffer()));
    const audio = execFileSync(ffmpeg, [
      '-v', 'error', '-i', designFile, '-vn', '-ac', '1', '-ar', '4000', '-f', 's16le', '-',
    ]);
    assert.ok(audio.some(byte => byte !== 0), 'The creative score was silent');
    const director = await request('/api/auto-edit', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        video_path: silentFixture,
        answers: { mode: 'short_auto', short_director: 'ai' },
      }),
    });
    assert.equal(director.status, 202);
    const { session_id: directorId } = await director.json();
    let unavailable;
    const directorDeadline = Date.now() + 10000;
    do {
      await sleep(100);
      unavailable = await (await request(`/api/auto-edit/status/${directorId}`)).json();
    } while (!['done', 'error'].includes(unavailable.status) && Date.now() < directorDeadline);
    assert.equal(unavailable.status, 'error', 'AI direction must not silently create a local edit');
    assert.match(unavailable.error, /المخرج الذكي/);
    assert.equal(unavailable.result, undefined);
    const corrupt = path.join(workspace, 'corrupt.mp4');
    await writeFile(corrupt, 'invalid MP4');
    const bad = await request('/api/auto-edit', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ video_path: corrupt, answers: { mode: 'short_auto' } }),
    });
    assert.equal(bad.status, 202);
    const { session_id: badId } = await bad.json();
    const failureDeadline = Date.now() + 10_000;
    let failed;
    do {
      await sleep(100);
      failed = await (await request(`/api/auto-edit/status/${badId}`)).json();
    } while (!['done', 'error'].includes(failed.status) && Date.now() < failureDeadline);
    assert.equal(failed.status, 'error');
    assert.equal(failed.result, undefined);
    const cancellable = await request('/api/auto-edit', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ video_path: fixture, answers: { mode: 'short_auto' } }),
    });
    assert.equal(cancellable.status, 202);
    const { session_id: cancelId } = await cancellable.json();
    const cancelRoute = `/api/auto-edit/cancel/${cancelId}`;
    assert.equal((await request(cancelRoute, { method: 'POST' })).status, 200);
    assert.equal((await request(cancelRoute, { method: 'POST' })).status, 200);
    const cancelled = await (await request(`/api/auto-edit/status/${cancelId}`)).json();
    assert.equal(cancelled.status, 'error');
    assert.equal(cancelled.result, undefined);
    console.log(`Short Auto smoke passed; result: ${file}`);
    verified = true;
    break;
  }
  assert(verified, 'Engine exited before the smoke test completed');
} finally {
  clearTimeout(startupTimeout);
  stdout.close();
  worker.kill();
  await exit;
}
