/* Interactive concept only: capture and transcription below are simulated. */
"use strict";

const $ = (selector) => document.querySelector(selector);
const icon = (name) => `<svg aria-hidden="true"><use href="#i-${name}"/></svg>`;
const sampleTranscript = "I’ve been thinking about making more space for the first version of an idea. Not everything needs to be polished before it’s worth keeping. Sometimes the useful part is just saying it out loud, listening back, and finding the thread. Next week, I want to try a short walk each morning and record whatever comes to mind.";
const sampleNote = "Make space for the first version of an idea.\n\nAn idea doesn’t need to be polished to be worth keeping. Saying it out loud, listening back, and finding the thread can be enough.\n\nNext week: take a short walk each morning and record whatever comes to mind.";
const state = {
  phase: "ready", elapsed: 0, selected: null, page: "Dictation", recovery: false,
  recordings: [], playing: null, operation: null, timeout: null, deleteID: null,
  startedAt: 0, baseElapsed: 0, paused: false, ptt: false, diskError: false,
  committed: 0, serial: 0, importGeneration: 0
};
const player = $("#player");
const formatTime = (seconds) => {
  const whole = Math.max(0, Math.floor(Number.isFinite(seconds) ? seconds : 0));
  const minutes = Math.floor(whole / 60);
  return `${String(minutes).padStart(2, "0")}:${String(whole % 60).padStart(2, "0")}`;
};
function escapeHTML(text) {
  return String(text).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}
function makeSample(overrides = {}) {
  return { id: `recording-${++state.serial}`, title: "Morning thoughts", when: "Today at 9:41 AM", duration: 19.491701,
    source: "Voice recording", url: "sample.m4a", synthetic: true, transcript: "", styled: false,
    language: "English", style: "Raw", ...overrides };
}
function selectedRecording() { return state.recordings.find((r) => r.id === state.selected); }
function notify(message, error = false) {
  $("#notice").textContent = message;
  $("#notice").hidden = false;
  $("#notice").classList.toggle("error", error);
}
function stopPlayback() {
  player.pause();
  state.playing = null;
}
function clearOperation() {
  if (state.timeout) clearTimeout(state.timeout);
  state.timeout = null;
  state.operation = null;
}
function reset() {
  clearOperation();
  stopPlayback();
  state.importGeneration++;
  for (const recording of state.recordings) {
    if (recording.url.startsWith("blob:")) URL.revokeObjectURL(recording.url);
  }
  Object.assign(state, { phase: "ready", elapsed: 0, selected: null, recovery: false, paused: false, ptt: false, diskError: false, committed: 0 });
  state.recordings = [
    makeSample(),
    makeSample({ title: "A thought on the walk home", when: "Yesterday at 5:18 PM", source: "Imported audio", transcript: sampleTranscript })
  ];
  $("#notice").hidden = true;
  $("#scenario").value = "ready";
  navigate("Dictation");
  render();
}
function startCapture({ elapsed = 0, ptt = false } = {}) {
  if (state.operation) return;
  stopPlayback();
  state.phase = "recording";
  state.elapsed = elapsed;
  state.baseElapsed = elapsed;
  state.startedAt = performance.now();
  state.committed = Math.floor(elapsed);
  state.paused = false;
  state.ptt = ptt;
  state.diskError = false;
  $("#notice").hidden = true;
  render();
}
function setCaptureStopped() {
  state.phase = "ready";
  state.elapsed = 0;
  state.committed = 0;
  state.paused = false;
  state.ptt = false;
}
function stopCapture() {
  if (state.phase !== "recording") return;
  if (state.ptt) {
    setCaptureStopped();
    notify("Push-to-talk ended. Its text would be pasted into the focused app; no audio or recovery file is kept.");
    render();
    return;
  }
  state.phase = "saving";
  renderCapture();
  state.timeout = setTimeout(() => {
    const r = makeSample({ title: "Untitled recording", when: "Just now", duration: state.elapsed, synthetic: true });
    state.recordings.unshift(r);
    state.selected = r.id;
    setCaptureStopped();
    state.timeout = null;
    notify("Recording kept on this Mac. Listen back or transcribe when you’re ready. (Simulated)");
    render();
  }, 650);
}
function togglePause() {
  if (state.phase !== "recording" || state.ptt) return;
  if (state.paused) {
    stopPlayback();
    state.startedAt = performance.now();
    state.baseElapsed = state.elapsed;
  } else {
    state.committed = Math.floor(state.elapsed);
  }
  state.paused = !state.paused;
  renderCapture();
}
function renderCapture() {
  const active = state.phase === "recording";
  const saving = state.phase === "saving";
  const permission = state.phase === "permission";
  const panel = $(".recorder-panel");
  panel.classList.toggle("is-recording", active && !state.paused);
  panel.classList.toggle("is-paused", active && state.paused);
  $("#capture-state").innerHTML = active
    ? `<span class="${state.paused ? "ready-dot" : "record-dot"}"></span>${state.ptt ? "Push to talk" : state.paused ? "Paused" : "Recording"}`
    : `${icon(permission || state.diskError ? "warning" : saving ? "clock" : "mic")}${permission ? "Microphone unavailable" : saving ? "Finishing the save…" : state.diskError ? "Recording stopped" : "Ready to record"}`;
  $("#record-clock").innerHTML = `${formatTime(state.elapsed)}<span>.${Math.floor((state.elapsed % 1) * 10)}</span>`;
  $("#record-hint").textContent = active
    ? state.ptt ? "Release Fn to paste. Audio is temporary." : state.paused ? "Take your time. The saved audio is safe." : "Take your time. The recorder is listening."
    : permission ? "Choose an input or check microphone access." : state.diskError ? "Saved audio is still available below." : "A little space to think out loud.";
  $("#record-button").innerHTML = active ? `${icon("stop")}${state.ptt ? "Release Fn" : "Stop & Keep"}` : saving ? "Saving…" : `<span class="button-record-dot"></span>Record`;
  $("#record-button").disabled = saving || permission || Boolean(state.operation);
  $("#pause-button").hidden = !active || state.ptt;
  $("#pause-button").innerHTML = `${icon(state.paused ? "play" : "pause")}${state.paused ? "Resume" : "Pause"}`;
  $("#microphone").disabled = active || saving;
  $("#input-state").textContent = permission ? "No input" : active ? state.paused ? "Paused" : "Input detected" : "Input ready";
  $("#disk-status").innerHTML = active
    ? state.ptt ? `${icon("clock")}<span>Temporary audio · not saved<small>No disk copy or crash recovery for push-to-talk.</small></span>`
      : `${icon("shield")}<span>${state.paused ? "Saved on this Mac" : "Saving to this Mac"} · ${formatTime(state.committed)} committed<small>${state.paused ? "Capture and timer are paused." : "Less than 1 second awaiting disk commit."} · Simulated</small></span>`
    : state.diskError ? `${icon("warning")}<span>Disk write failed. Capture stopped.<small>Keep the saved audio; free space before recording again.</small></span>`
      : permission ? `${icon("warning")}<span>Microphone access is needed to record.<small>Importing and playing audio are still available.</small></span>`
        : `${icon("shield")}<span>Audio saves to this Mac while you record.<small>Push-to-talk is temporary and isn’t saved.</small></span>`;
  $("#recording-footnote").textContent = active && !state.ptt
    ? "The saved portion is recoverable after a crash. Audio still awaiting a disk commit may be lost."
    : "Stop to keep the recording. Listen and transcribe whenever you’re ready.";
  $("#nav-recording").hidden = !active;
  $("#persistent-recording").hidden = !active || state.page === "Dictation";
  $("#persistent-label").textContent = `${state.paused ? "Paused" : state.ptt ? "Push to talk" : "Recording"} · ${formatTime(state.elapsed)}`;
}
function renderList() {
  $("#recovery-notice").hidden = !state.recovery;
  const recovered = state.recordings.find((r) => r.interrupted);
  if (recovered) $("#recovery-length").textContent = formatTime(recovered.duration);
  $("#recording-list").hidden = state.recordings.length === 0;
  $("#empty-list").hidden = state.recordings.length !== 0;
  $("#recording-list").innerHTML = state.recordings.map((r) => `
    <div class="recording-row ${r.interrupted ? "interrupted" : ""} ${r.id === state.selected ? "is-selected" : ""}">
      <span class="row-icon">${icon(r.interrupted ? "clock" : r.source === "Imported audio" ? "file" : "wave")}</span>
      <button class="row-text" data-action="select" data-id="${r.id}" aria-expanded="${r.id === state.selected}"><strong>${escapeHTML(r.title)}</strong><small>${escapeHTML(r.when)} · ${escapeHTML(r.source)}</small></button>
      <span class="row-badge ${r.interrupted ? "recovered" : ""}">${r.interrupted ? "Interrupted" : r.transcript ? "Transcribed" : "Audio saved"}</span>
      <span class="row-duration">${formatTime(r.duration)}</span>
      <button class="row-play" data-action="play" data-id="${r.id}" aria-label="${state.playing === r.id ? "Pause" : "Play"} ${escapeHTML(r.title)}">${icon(state.playing === r.id ? "pause" : "play")}</button>
      <button class="row-open" data-action="select" data-id="${r.id}">${r.transcript ? "Open" : "Review"}</button>
    </div>`).join("");
}
function renderDetail() {
  const r = selectedRecording();
  const detail = $("#recording-detail");
  detail.hidden = !r;
  if (!r) return;
  const busy = state.operation === r.id;
  const captureBusy = state.phase === "recording" || state.phase === "saving";
  detail.innerHTML = `
    <div class="detail-heading"><div><h3>${escapeHTML(r.title)}</h3><p>${r.interrupted ? "Recovered audio" : escapeHTML(r.source)} · ${formatTime(r.duration)}${r.synthetic ? " · Synthetic sample audio" : " · Local file"}</p></div><button class="icon-button" data-action="close" aria-label="Close recording">${icon("close")}</button></div>
    <div class="player-line">
      <button class="player-button" data-action="play" data-id="${r.id}" aria-label="${state.playing === r.id ? "Pause audio" : "Play audio"}">${icon(state.playing === r.id ? "pause" : "play")}</button>
      <span class="player-time" id="play-position">00:00</span>
      <input id="seek" aria-label="Playback position" type="range" min="0" max="${r.duration}" step="0.1" value="0">
      <span class="player-time">${formatTime(r.duration)}</span><button class="speed-button" data-action="speed" aria-label="Playback speed">${player.playbackRate}×</button>
    </div>
    ${r.interrupted ? `<p class="detail-caveat">${icon("shield")}Recovered through ${formatTime(r.duration)}, the last successful disk commit. Any uncommitted tail can’t be recovered.</p>` : ""}
    ${r.synthetic ? `<p class="detail-caveat">${icon("wave")}Playback uses a short synthetic sample, not a real microphone recording.</p>` : ""}
    <div class="processing-options">
      <label>Language<select id="language" ${busy ? "disabled" : ""}><option ${r.language === "English" ? "selected" : ""}>English</option><option ${r.language === "French" ? "selected" : ""}>French</option><option ${r.language === "Spanish" ? "selected" : ""}>Spanish</option></select></label>
      <label>Writing style<select id="style" ${busy ? "disabled" : ""}>${["Raw", "Polished", "Diary", "Professional", "Like me"].map((s) => `<option ${r.style === s ? "selected" : ""}>${s}</option>`).join("")}</select></label>
      <button class="primary" data-action="transcribe" ${busy || captureBusy || state.operation ? "disabled" : ""}>${icon("pencil")}${busy ? "Processing…" : r.transcript ? "Process Again" : "Transcribe"}</button>
    </div>
    ${captureBusy ? `<p class="detail-caveat">Stop recording before starting transcription.</p>` : ""}
    ${busy ? `<div class="processing-state" role="status"><strong>Transcribing on this Mac…</strong><progress aria-label="Transcription progress"></progress><p>Simulated processing. Your original audio stays untouched.</p><button data-action="cancel-processing">Cancel Processing</button></div>` : ""}
    ${r.transcript && !busy ? `
      <div class="transcript-block"><div class="section-topline"><strong>${r.styled ? `${escapeHTML(r.style)} version` : "Transcript"}</strong><span class="muted">Sample text · not speech recognition</span></div>
      <p class="transcript-text">${escapeHTML(r.styled ? sampleNote : r.transcript).replace(/\n/g, "<br>")}</p>
      ${r.styled ? `<details><summary>Original transcript</summary><p class="transcript-text">${escapeHTML(r.transcript)}</p></details>` : ""}
      <div class="transcript-actions"><span class="muted">Audio retained with this recording.</span><div><button data-action="copy">${icon("copy")}Copy Text</button><button data-action="file-note">${icon("book")}File as Note…</button></div></div></div>` : ""}
    <div class="detail-bottom"><span>Original audio is never changed by transcription.</span><div><button class="icon-button" data-action="download" aria-label="Save audio as a file" title="Save audio as a file">${icon("download")}</button><button class="icon-button" data-action="delete" aria-label="Delete recording" title="Delete recording" ${busy ? "disabled" : ""}>${icon("trash")}</button></div></div>`;
  updatePlayPosition();
}
function render() { renderCapture(); renderList(); renderDetail(); }
function navigate(page) {
  state.page = page;
  const isDictation = page === "Dictation";
  $("#dictation-page").hidden = !isDictation;
  $("#other-page").hidden = isDictation;
  $("#other-page-title").textContent = page;
  for (const button of document.querySelectorAll(".nav-item")) {
    const selected = button.dataset.page === page;
    button.classList.toggle("selected", selected);
    if (selected) button.setAttribute("aria-current", "page");
    else button.removeAttribute("aria-current");
    button.setAttribute("aria-label", button.dataset.page);
    button.title = button.dataset.page;
  }
  renderCapture();
}
async function playRecording(id) {
  const r = state.recordings.find((item) => item.id === id);
  if (!r) return;
  if (state.playing === id) {
    stopPlayback();
    renderList();
    renderDetail();
    return;
  }
  if (state.phase === "recording" && !state.paused) {
    notify("Pause or stop the recording before playing audio to keep playback out of the microphone.", true);
    return;
  }
  stopPlayback();
  const previous = player.dataset.recording;
  if (previous !== id) {
    player.src = r.url;
    player.dataset.recording = id;
  }
  state.selected = id;
  state.playing = id;
  renderList();
  renderDetail();
  try { await player.play(); }
  catch (error) {
    if (error.name === "AbortError") return;
    state.playing = null;
    notify("This audio couldn’t be played. Try a supported M4A, MP3 or WAV file.", true);
    renderList();
    renderDetail();
  }
}
function updatePlayPosition() {
  const r = selectedRecording();
  if (!r || player.dataset.recording !== r.id) return;
  const time = player.currentTime;
  if ($("#play-position")) $("#play-position").textContent = formatTime(time);
  if ($("#seek")) {
    $("#seek").max = Number.isFinite(player.duration) ? player.duration : r.duration;
    $("#seek").value = String(time);
  }
}
function processRecording() {
  const r = selectedRecording();
  if (!r || state.operation || state.phase === "recording" || state.phase === "saving") return;
  r.style = $("#style").value;
  r.language = $("#language").value;
  state.operation = r.id;
  state.recovery = false;
  $("#notice").hidden = true;
  render();
  state.timeout = setTimeout(() => {
    if (!state.recordings.includes(r)) return;
    r.transcript = sampleTranscript;
    r.styled = r.style !== "Raw";
    r.interrupted = false;
    clearOperation();
    notify("Sample transcript ready. In the app, this would use the same local speech and writing models as live dictation.");
    render();
  }, 2200);
}
function selectRecording(id) {
  if (state.selected !== id) stopPlayback();
  state.selected = id;
  renderList();
  renderDetail();
}
function simulateScenario(value) {
  reset();
  $("#scenario").value = value;
  if (value === "recording") startCapture({ elapsed: 84 });
  if (value === "ptt") startCapture({ elapsed: 6, ptt: true });
  if (value === "permission") {
    state.phase = "permission";
    notify("Microphone access is unavailable. The finished app would link to Settings › Permissions; importing audio still works.", true);
  }
  if (value === "recovery" || value === "disk") {
    const r = makeSample({ title: "Untitled recording", when: "Today at 10:12 AM", interrupted: true, source: "Voice recording" });
    state.recordings.unshift(r);
    state.recovery = true;
    if (value === "disk") {
      state.diskError = true;
      state.selected = r.id;
      notify("The disk couldn’t keep up. Recording stopped; audio through the last successful commit is available below. Free space before trying again.", true);
    }
  }
  render();
}
async function importFile(file) {
  if (!file) return;
  if (!/\.(m4a|mp3|wav|wave|aiff?|caf|flac|ogg|opus|aac|mp4)$/i.test(file.name) && !file.type.startsWith("audio/")) {
    notify("Choose an audio file, such as M4A, MP3 or WAV. Nothing was imported.", true);
    return;
  }
  if (file.size === 0) {
    notify("This file is empty. Choose an audio recording with sound.", true);
    return;
  }
  const generation = state.importGeneration;
  const url = URL.createObjectURL(file);
  const metadata = new Audio();
  metadata.preload = "metadata";
  let timer;
  try {
    const duration = await new Promise((resolve, reject) => {
      metadata.onloadedmetadata = () => {
        if (Number.isFinite(metadata.duration) && metadata.duration > 0) resolve(metadata.duration);
        else reject(new Error("No usable duration"));
      };
      metadata.onerror = () => reject(new Error("Unsupported audio"));
      timer = setTimeout(() => reject(new Error("Audio load timed out")), 10000);
      metadata.src = url;
    });
    if (generation !== state.importGeneration) { URL.revokeObjectURL(url); return; }
    const r = makeSample({ title: file.name, when: "Just imported", duration, source: "Imported audio", url, synthetic: false });
    state.recordings.unshift(r);
    navigate("Dictation");
    selectRecording(r.id);
    notify("Audio imported locally. Listen back, then choose a language and style to transcribe. Processing is simulated in this concept.");
    render();
  } catch {
    URL.revokeObjectURL(url);
    if (generation === state.importGeneration) notify("This file couldn’t be read. Try exporting it as M4A, MP3 or WAV, then import again.", true);
  } finally {
    clearTimeout(timer);
    metadata.removeAttribute("src");
    metadata.load();
  }
}
$("#record-button").addEventListener("click", () => state.phase === "recording" ? stopCapture() : startCapture());
$("#pause-button").addEventListener("click", togglePause);
$("#reset").addEventListener("click", reset);
$("#theme").addEventListener("click", () => {
  const light = document.documentElement.classList.toggle("light");
  $("#theme").textContent = light ? "Dark" : "Light";
});
$("#scenario").addEventListener("change", (event) => simulateScenario(event.target.value));
$("#review-recovery").addEventListener("click", () => {
  const r = state.recordings.find((item) => item.interrupted);
  if (!r) return;
  selectRecording(r.id);
  $("#recording-detail").scrollIntoView({ behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth", block: "nearest" });
});
for (const selector of ["#import-button", "#empty-import"]) $(selector).addEventListener("click", () => $("#file-input").click());
$("#file-input").addEventListener("change", (event) => {
  importFile(event.target.files[0]);
  event.target.value = "";
});
for (const button of document.querySelectorAll(".nav-item")) button.addEventListener("click", () => navigate(button.dataset.page));
for (const selector of ["#back-to-recording", "#return-dictation"]) $(selector).addEventListener("click", () => navigate("Dictation"));
$("#recording-list").addEventListener("click", (event) => {
  const button = event.target.closest("button[data-action]");
  if (!button) return;
  if (button.dataset.action === "play") playRecording(button.dataset.id);
  else selectRecording(button.dataset.id);
});
$("#recording-detail").addEventListener("change", (event) => {
  const r = selectedRecording();
  if (!r) return;
  if (event.target.id === "style") r.style = event.target.value;
  if (event.target.id === "language") r.language = event.target.value;
});
$("#recording-detail").addEventListener("input", (event) => {
  if (event.target.id === "seek") {
    const r = selectedRecording();
    if (r && player.dataset.recording !== r.id) { player.src = r.url; player.dataset.recording = r.id; }
    player.currentTime = Number(event.target.value);
    updatePlayPosition();
  }
});
$("#recording-detail").addEventListener("click", async (event) => {
  const action = event.target.closest("[data-action]")?.dataset.action;
  const r = selectedRecording();
  if (!action || !r) return;
  if (action === "close") { stopPlayback(); state.selected = null; render(); }
  if (action === "play") await playRecording(r.id);
  if (action === "speed") {
    const speeds = [1, 1.25, 1.5, 2];
    player.playbackRate = speeds[(speeds.indexOf(player.playbackRate) + 1) % speeds.length];
    renderDetail();
  }
  if (action === "transcribe") processRecording();
  if (action === "cancel-processing") { clearOperation(); notify("Processing cancelled. The original recording is still available."); render(); }
  if (action === "copy") {
    try { await navigator.clipboard.writeText(r.styled ? sampleNote : r.transcript); notify("Text copied."); }
    catch { notify("Clipboard access was blocked. Select the transcript text and copy it manually.", true); }
  }
  if (action === "file-note") $("#filing-dialog").showModal();
  if (action === "download") {
    const link = document.createElement("a");
    link.href = r.url;
    link.download = r.synthetic ? "audio-pencil-synthetic-sample.m4a" : r.title;
    link.click();
  }
  if (action === "delete") {
    state.deleteID = r.id;
    $("#delete-description").textContent = `“${r.title}” · ${formatTime(r.duration)}`;
    $("#delete-dialog").showModal();
  }
});
$("#delete-dialog").addEventListener("close", () => {
  if ($("#delete-dialog").returnValue !== "delete") return;
  const r = state.recordings.find((item) => item.id === state.deleteID);
  stopPlayback();
  if (r?.url.startsWith("blob:")) URL.revokeObjectURL(r.url);
  state.recordings = state.recordings.filter((item) => item.id !== state.deleteID);
  state.selected = null;
  state.recovery = state.recordings.some((item) => item.interrupted);
  render();
});
player.addEventListener("timeupdate", updatePlayPosition);
player.addEventListener("ended", () => { state.playing = null; renderList(); renderDetail(); });
player.addEventListener("error", () => {
  if (!state.playing) return;
  state.playing = null;
  notify("Playback failed. Keep the original file and try importing a supported audio format.", true);
  renderList();
  renderDetail();
});
document.addEventListener("dragover", (event) => {
  if (!event.dataTransfer.types.includes("Files")) return;
  event.preventDefault();
  $("main").classList.add("drop-target");
});
document.addEventListener("dragleave", (event) => { if (!event.relatedTarget) $("main").classList.remove("drop-target"); });
document.addEventListener("drop", (event) => {
  event.preventDefault();
  $("main").classList.remove("drop-target");
  const files = Array.from(event.dataTransfer.files);
  if (files.length > 1) { notify("Import one recording at a time in this concept.", true); return; }
  importFile(files[0]);
});
document.addEventListener("keydown", (event) => {
  if (event.code !== "Space" || /INPUT|SELECT|TEXTAREA|BUTTON/.test(document.activeElement.tagName) || document.querySelector("dialog[open]")) return;
  if (state.page !== "Dictation" || !["ready", "recording"].includes(state.phase) || state.operation) return;
  event.preventDefault();
  if (state.phase === "recording") togglePause();
  else startCapture();
});
window.addEventListener("beforeunload", () => {
  for (const r of state.recordings) if (r.url.startsWith("blob:")) URL.revokeObjectURL(r.url);
});
$("#live-wave").innerHTML = Array.from({ length: 60 }, (_, i) => `<i style="--n:${i};--bar-height:${10 + Math.abs(Math.sin(i * 1.71) * Math.cos(i * .29)) * 55}px"></i>`).join("");
setInterval(() => {
  if (state.phase !== "recording" || state.paused) return;
  state.elapsed = state.baseElapsed + (performance.now() - state.startedAt) / 1000;
  state.committed = Math.floor(state.elapsed);
  renderCapture();
}, 100);
reset();
