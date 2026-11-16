// ============================================================
// LP のアプリ画面の再現
//
//   夜、1日を振り返りながら独り言を言っている人の画面を、ブラウザの中で動かす。
//   話している間は「.」が増え、話し終えると文字が打ち出されてメモが 1 つ増える。
//   背景には、話している声に合わせて揺れる波線を流す。
//
//   見た目と動きの数値は、アプリ本体の次の実装に合わせている。
//   - 一覧の文字・行・余白 …… ios/Runner/NativeMemoList.swift（style.css の .demo__memos）
//   - 「.」の増え方 ……………… 同ファイルの MemoSpeakingDotsView
//   - 文字の打ち出し ………… lib/widgets/typewriter_text.dart
//   - 背景の波線 ………………… lib/widgets/listening_backdrop.dart
//   - 台本と話すリズム ……… lib/pages/dev/recording/recording_listening_simulator.dart
// ============================================================
(() => {
  "use strict";

  const screen = document.querySelector(".demo__screen");
  if (!screen) return;

  const memoList = screen.querySelector(".demo__memos");
  const waveCanvas = screen.querySelector(".demo__wave");

  // ---------------------------------
  // 台本（[話す文, 話題が変わる所の間の目安 ms または null]）
  // ---------------------------------
  const SCRIPT = [
  ["Okay. Long day. Let me just get everything out of my head before I forget it.", null],
  ["Call the dentist before Wednesday. I keep forgetting that one.", null],
  ["And the car needs an oil change. The little light came on again this morning.", null],
  ["Mom's birthday is on the 24th. Maybe a scarf? She said her old one is falling apart.", null],
  ["Or a nice teapot. She's been drinking a lot of tea lately.", null],
  ["Actually, I could just ask Dad. He always knows what she wants but never says it.", 2000],
  ["The meeting today went better than I expected. I should stop assuming the worst before these things.", null],
  ["Ken's idea about splitting the project into two phases was really good.", null],
  ["I should tell him that tomorrow. People don't hear that enough.", null],
  ["Reply to Sarah's email about the budget. It's been three days.", 2000],
  ["Idea for the weekend: take a train somewhere I've never been. No plans, just walk around.", null],
  ["Maybe the coast. It's supposed to be sunny on Saturday.", null],
  ["Eggs, milk, and those coffee beans from the place near the station.", null],
  ["Oh, and dish soap. We're almost out.", null],
  ["I think I'm tired because I've been going to bed at one every night. Lights out by midnight. Seriously.", null],
  ["Phone stays in the kitchen tonight.", 2000],
  ["That book Yuki recommended. What was it called? Something about the ocean.", null],
  ["I'll text her and ask. She'll laugh at me for forgetting again.", null],
  ["Dinner tomorrow: the pasta with lemon and garlic. Quick, and I have everything except parsley.", null],
  ["Why do I always buy parsley and then throw half of it away.", null],
  ["Maybe grow some on the balcony. How hard can it be.", null],
  ["Famous last words.", 2000],
  ["I really want to start running again. Even just twice a week.", null],
  ["The trick last time was going right after work, before I sat down. Once I sit down, it's over.", null],
  ["Running shoes. Are they still in the closet? I think they're behind the vacuum.", null],
  ["Rent goes out on the first. Check the account on Thursday.", null],
  ["And cancel that streaming thing I never watch. Eleven dollars a month for nothing.", 2000],
  ["Something I noticed today: I'm much calmer when I eat lunch away from my desk.", null],
  ["Small thing, but I want to keep doing that.", null],
  ["The presentation next Friday. Open with the customer story, not the numbers.", null],
  ["Numbers second. Nobody remembers a chart.", null],
  ["Ask Tom if he can look over the slides on Wednesday afternoon.", 2000],
  ["I haven't called Grandma in almost a month. That's not okay.", null],
  ["Sunday morning. She's always up early. Call her then.", null],
  ["She'll ask if I'm eating properly. I'll say yes. Which is half true.", 2000],
  ["Random thought: what if the kitchen table went by the window instead?", null],
  ["More light in the morning. Worth trying this weekend.", null],
  ["Return the jacket. The receipt is in the blue folder, I'm pretty sure.", null],
  ["Thirty days, so by the end of next week.", null],
  ["That podcast about sleep was interesting. No screens an hour before bed.", null],
  ["Which, again, means phone in the kitchen.", 2000],
  ["Today was good, actually. Not perfect, but good.", null],
  ["The coffee this morning, the walk to the station. The sky was ridiculous.", null],
  ["I want to remember days like this.", 2000],
  ["For Mika's party on Saturday: wine, and the board game she liked.", null],
  ["Wait, Saturday was the coast. Okay, coast on Sunday then.", null],
  ["Or next weekend. No need to cram everything in.", 2000],
  ["Little project: a shelf by the front door. Keys, mail, sunglasses. Stop losing my keys.", null],
  ["Measure the wall first. Don't eyeball it like last time.", null],
  ["Ask the landlord about the bathroom fan. It sounds like a helicopter.", null],
  ["I keep saying I'll learn to cook Thai food. Start with green curry.", null],
  ["There's that shop near the office with the curry paste in a jar. Cheating, but fine.", 2000],
  ["Should I take that online course? It's a lot of evenings.", null],
  ["Maybe start with one module and see how it feels.", null],
  ["Don't decide tonight. Tired brain makes bad decisions.", null],
  ["Tom said a new café opened next to the library. Try it this week.", 2000],
  ["Write a thank-you card for the Nakamuras. They really helped with the move.", null],
  ["Buy stamps. Do people still buy stamps? I do, apparently.", null],
  ["I was short with Ren on the phone today. Not fair. He didn't do anything.", null],
  ["Apologize tomorrow. Keep it simple.", null],
  ["The plants need water. The big one by the window looks sad.", null],
  ["Laundry tomorrow morning, before it gets out of hand.", 2000],
  ["Okay, what am I actually worried about.", null],
  ["The review at work, mostly. But I've done the work. It'll be fine.", null],
  ["Write down three things I did well this quarter, just to have them ready.", null],
  ["One: shipped the onboarding update on time.", null],
  ["Two: helped the new people settle in.", null],
  ["Three: stopped saying yes to every meeting. That one counts.", 2000],
  ["Summer trip. Mom and Dad mentioned Kyoto again.", null],
  ["Look at dates in early July before it gets expensive.", null],
  ["Back up the photos. Thousands of them, just sitting on the phone.", null],
  ["Haircut. It's been, what, two months?", null],
  ["Book it for Saturday morning, before Mika's party.", 2000],
  ["I like this. Just saying things out loud. It's quieter in my head now.", null],
  ["Water bottle on the nightstand. Alarm at seven.", null],
  ["Okay. I think that's everything.", null],
  ["Good night.", 3000],
  ];

  // ---------------------------------
  // 話すリズム（アプリの収録用シミュレーターと同じ値）
  // ---------------------------------
  const FIRST_SPEECH_DELAY_MS = 500;
  const SPEAKING_MS_PER_CHARACTER = 28;
  const MIN_SPEAKING_MS = 600;
  const MAX_SPEAKING_MS = 5500;
  const THINKING_WHILE_TALKING_RATE = 0.15;
  const THINKING_WHILE_TALKING_FACTOR = 1.5;
  const BASE_TRANSCRIPTION_MS = 200;
  const TRANSCRIPTION_MS_PER_CHARACTER = 3;
  const MAX_TRANSCRIPTION_JITTER_MS = 500;

  // 台本を言い終えてから、一覧を消して話し直すまで
  const RESTART_WAIT_MS = 4000;
  const FADE_OUT_MS = 1000;

  // 画面の外に出たメモは、この数を超えたら古いものから消す（一覧が重くならないように）
  const MAX_KEPT_MEMOS = 30;

  // ---------------------------------
  // 「.」と打ち出し（アプリと同じ値）
  // ---------------------------------
  const DOT_INTERVAL_MS = 500;
  const MAX_DOT_COUNT = 10;
  const TYPING_TICK_MS = 30;
  const MAX_TYPING_MS = 1800;

  // ---------------------------------
  // 行ごとの揺らぎ（0.0 以上 1.0 未満）。行の番号から決めるので、毎回同じリズムになる
  // ---------------------------------
  function variation(index, salt) {
    return (((index + 1) * 2654435761 + salt * 40503) % 1000) / 1000;
  }

  // 次の発話までの間：すぐ言い足す・ふつうに続ける・少し考え込む、を混ぜる
  function pauseAfterMs(index, scriptedPauseMs) {
    const roll = variation(index, 3);
    const spread = variation(index, 4);
    if (scriptedPauseMs !== null) return Math.round(scriptedPauseMs * (0.8 + 0.6 * spread));
    if (roll < 0.35) return Math.round(300 + 600 * spread);
    if (roll < 0.8) return Math.round(800 + 800 * spread);
    return Math.round(2000 + 1500 * spread);
  }

  // 1 行ぶんの話す時間・文字になるまでの時間・次までの間
  function timingOf(index) {
    const [text, scriptedPauseMs] = SCRIPT[index];

    let speakingFactor = 0.75 + 0.6 * variation(index, 1);
    if (variation(index, 5) < THINKING_WHILE_TALKING_RATE) {
      speakingFactor *= THINKING_WHILE_TALKING_FACTOR;
    }
    const speakingMs = Math.min(
      MAX_SPEAKING_MS,
      Math.max(MIN_SPEAKING_MS, Math.round(text.length * SPEAKING_MS_PER_CHARACTER * speakingFactor)),
    );
    const transcriptionMs =
      BASE_TRANSCRIPTION_MS +
      text.length * TRANSCRIPTION_MS_PER_CHARACTER +
      Math.round(MAX_TRANSCRIPTION_JITTER_MS * variation(index, 2));

    return { text, speakingMs, transcriptionMs, pauseMs: pauseAfterMs(index, scriptedPauseMs) };
  }

  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  // ---------------------------------
  // 画面の状態
  // ---------------------------------
  const state = {
    speaking: false, // 話している最中か
    awaitingText: false, // 話し終えて、文字になるのを待っているか
    typing: false, // 直前のメモを打ち出している最中か
    speakingStartedAt: 0,
    speakingSeconds: 0,
  };

  // ---------------------------------
  // 「.」：話し始めてから文字が届くまで、次のメモが入る場所に出す。
  //   前のメモを打ち出している間は、打ち終わってから出す
  // ---------------------------------
  let dotsElement = null;
  let dotsTimer = null;

  function updateDots() {
    const shouldShow = (state.speaking || state.awaitingText) && !state.typing;

    if (shouldShow && !dotsElement) {
      dotsElement = document.createElement("p");
      dotsElement.className = "demo__dots";
      memoList.appendChild(dotsElement);

      let dotCount = 0;
      dotsTimer = setInterval(() => {
        dotCount = dotCount >= MAX_DOT_COUNT ? 0 : dotCount + 1;
        // 0 個のときも行の高さを保つため、幅の無い空白を入れておく
        dotsElement.textContent = dotCount === 0 ? "​" : ".".repeat(dotCount);
      }, DOT_INTERVAL_MS);
      dotsElement.textContent = "​";
    }

    if (!shouldShow && dotsElement) {
      clearInterval(dotsTimer);
      dotsElement.remove();
      dotsElement = null;
    }
  }

  // ---------------------------------
  // メモを 1 つ足して打ち出す。長い文でも MAX_TYPING_MS 以内に打ち終わるよう、1 回に進める文字数を増やす。
  //   まだ打っていない残りも透明な文字として最初から置き、メモの高さと折り返しを打ち始めから確定させる。
  //   こうしないと、打つたびに行が増えたり単語が次の行へ飛んだりして、一覧が上下にがたつく
  // ---------------------------------
  function addMemo(text) {
    const memo = document.createElement("p");
    memo.className = "demo__memo";
    const typedPart = document.createElement("span");
    const restPart = document.createElement("span");
    restPart.className = "demo__memo-rest";
    restPart.textContent = text;
    memo.append(typedPart, restPart);
    memoList.appendChild(memo);

    while (memoList.querySelectorAll(".demo__memo").length > MAX_KEPT_MEMOS) {
      memoList.querySelector(".demo__memo").remove();
    }

    const characters = Array.from(text);
    const maxTicks = Math.floor(MAX_TYPING_MS / TYPING_TICK_MS);
    const charactersPerTick = Math.max(1, Math.ceil(characters.length / maxTicks));
    let visibleCount = 0;

    state.typing = true;
    updateDots();

    const typingTimer = setInterval(() => {
      visibleCount = Math.min(visibleCount + charactersPerTick, characters.length);
      typedPart.textContent = characters.slice(0, visibleCount).join("");
      restPart.textContent = characters.slice(visibleCount).join("");
      if (visibleCount >= characters.length) {
        clearInterval(typingTimer);
        state.typing = false;
        updateDots();
      }
    }, TYPING_TICK_MS);
  }

  // ---------------------------------
  // 台本を上から順に話す。言い終えたら一覧を消して、最初から話し直す
  // ---------------------------------
  async function talk() {
    for (;;) {
      await sleep(FIRST_SPEECH_DELAY_MS);

      for (let index = 0; index < SCRIPT.length; index++) {
        const { text, speakingMs, transcriptionMs, pauseMs } = timingOf(index);

        state.speaking = true;
        state.speakingStartedAt = performance.now();
        state.speakingSeconds = speakingMs / 1000;
        updateDots();
        await sleep(speakingMs);

        state.speaking = false;
        state.awaitingText = true;
        updateDots();
        await sleep(transcriptionMs);

        state.awaitingText = false;
        addMemo(text);
        await sleep(pauseMs);
      }

      await sleep(RESTART_WAIT_MS);
      memoList.classList.add("is-fading");
      await sleep(FADE_OUT_MS);
      memoList.replaceChildren();
      dotsElement = null;
      memoList.classList.remove("is-fading");
    }
  }

  // ---------------------------------
  // 話している声の大きさ（0.0〜1.0）。アプリの収録用シミュレーターと同じ式で、音節と句の揺れを重ねる
  // ---------------------------------
  function currentLevel(now) {
    if (!state.speaking) return 0;
    const elapsed = (now - state.speakingStartedAt) / 1000;

    const attack = Math.min(1, Math.max(0, elapsed / 0.1));
    const release = Math.min(1, Math.max(0, (state.speakingSeconds - elapsed) / 0.16));
    const syllable =
      0.55 + 0.3 * Math.sin(elapsed * 2 * Math.PI * 5.4) + 0.15 * Math.sin(elapsed * 2 * Math.PI * 8.9 + 1.3);
    const phrase = 0.75 + 0.25 * Math.sin(elapsed * 2 * Math.PI * 1.1 + 0.7);

    return Math.min(1, Math.max(0, 0.85 * attack * release * syllable * phrase));
  }

  // ---------------------------------
  // 背景の波線（アプリの ListeningBackdrop と同じ作り）
  //   声の大きさをなめらかにして一定間隔で履歴に積み、画面に固定した頂点ごとに「何秒前の音か」を引いて結ぶ
  // ---------------------------------
  const WAVE = {
    visibleSeconds: 1.68, // 右端から左端まで流れるのにかかる秒数
    historyStepSec: 0.02, // 声の大きさを履歴へ記録する間隔
    vertexSpacingPt: 2, // 線の頂点の間隔（CSS ピクセル）
    strokeWidthPt: 0.5,
    wavesAcross: 2,
    attackTauSec: 0.02,
    releaseTauSec: 0.3,
    gainExponent: 0.5,
    idleAmplitude: 0.06,
    idleFrequencyHz: 0.4,
    maxAmplitudeFactor: 0.4,
    color: "#cfd1d4",
  };

  const wave = {
    // 末尾が新しい。画面に収まる時間ぶん＋補間用の余り 2 つを保持する
    history: new Array(Math.ceil(WAVE.visibleSeconds / WAVE.historyStepSec) + 2).fill(0),
    smoothed: 0,
    current: 0,
    sinceLastRecordSec: 0, // 履歴の末尾を記録してからの経過秒数
    idlePhase: 0,
    lastTime: 0,
  };

  const context = waveCanvas.getContext("2d");

  function resizeWave() {
    const ratio = window.devicePixelRatio || 1;
    waveCanvas.width = Math.round(waveCanvas.clientWidth * ratio);
    waveCanvas.height = Math.round(waveCanvas.clientHeight * ratio);
  }

  function advanceWave(dtSec, now) {
    const raw = currentLevel(now);
    const tau = raw > wave.smoothed ? WAVE.attackTauSec : WAVE.releaseTauSec;
    wave.smoothed += (raw - wave.smoothed) * (1 - Math.exp(-dtSec / tau));
    wave.current = Math.min(1, Math.max(0, Math.pow(wave.smoothed, WAVE.gainExponent)));

    // 無音でも、かすかに揺らし続ける
    const idle = WAVE.idleAmplitude * (0.5 + 0.5 * Math.sin(wave.idlePhase));
    if (wave.current < idle) wave.current = idle;

    wave.idlePhase += WAVE.idleFrequencyHz * 2 * Math.PI * dtSec;

    // 一定間隔ごとに、いまの大きさを履歴の末尾へ記録し、古いものを捨てる
    wave.sinceLastRecordSec += dtSec;
    while (wave.sinceLastRecordSec >= WAVE.historyStepSec) {
      wave.sinceLastRecordSec -= WAVE.historyStepSec;
      wave.history.shift();
      wave.history.push(wave.current);
    }
  }

  // 指定した秒数前の大きさを、履歴から線形補間して返す
  function levelAt(ageSec) {
    const history = wave.history;
    const sinceLast = wave.sinceLastRecordSec;

    // 末尾の記録より新しい区間は、いまの大きさと末尾の記録をつなぐ
    if (ageSec <= sinceLast) {
      if (sinceLast <= 0) return wave.current;
      return lerp(wave.current, history[history.length - 1], ageSec / sinceLast);
    }

    // それより古い区間は、隣り合う 2 つの記録をつなぐ
    const stepsBack = (ageSec - sinceLast) / WAVE.historyStepSec;
    const newerIndex = history.length - 1 - Math.floor(stepsBack);
    const olderIndex = newerIndex - 1;
    if (olderIndex < 0) return history[0];
    return lerp(history[newerIndex], history[olderIndex], stepsBack - Math.floor(stepsBack));
  }

  function lerp(from, to, ratio) {
    return from + (to - from) * ratio;
  }

  function drawWave() {
    const width = waveCanvas.width;
    const height = waveCanvas.height;
    context.clearRect(0, 0, width, height);

    if (width <= 0) return;

    const centerY = height / 2;
    const maxHalf = height * WAVE.maxAmplitudeFactor;
    const carrier = (2 * Math.PI * WAVE.wavesAcross) / width;

    // 右端が「いま」、左端が visibleSeconds 秒前
    const secondsPerPx = WAVE.visibleSeconds / width;

    // 頂点は画面上の位置に固定し、左端から右端までちょうど並べる
    const vertexCount = Math.max(1, Math.ceil(waveCanvas.clientWidth / WAVE.vertexSpacingPt));

    context.beginPath();
    for (let vertexIndex = 0; vertexIndex <= vertexCount; vertexIndex++) {
      const x = (width * vertexIndex) / vertexCount;
      const ageSec = (width - x) * secondsPerPx;
      const y = centerY + levelAt(ageSec) * maxHalf * Math.sin(x * carrier);
      if (vertexIndex === 0) {
        context.moveTo(x, y);
      } else {
        context.lineTo(x, y);
      }
    }
    context.strokeStyle = WAVE.color;
    context.lineWidth = Math.max(1, (WAVE.strokeWidthPt * width) / 440);
    context.lineCap = "round";
    context.lineJoin = "round";
    context.stroke();
  }

  function onFrame(now) {
    // タブを離れて戻ったときなどに大きく飛ばないよう、1 回に進める時間は 0.1 秒までにする
    const dtSec = wave.lastTime ? Math.min(0.1, (now - wave.lastTime) / 1000) : 0;
    wave.lastTime = now;
    if (dtSec > 0) advanceWave(dtSec, now);
    drawWave();
    requestAnimationFrame(onFrame);
  }

  // ---------------------------------
  // 始める。動きを減らす設定のときは、台本の最後のほうを止まった状態で並べるだけにする
  // ---------------------------------
  new ResizeObserver(resizeWave).observe(waveCanvas);
  resizeWave();

  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    for (const [text] of SCRIPT.slice(-12)) {
      const memo = document.createElement("p");
      memo.className = "demo__memo";
      memo.textContent = text;
      memoList.appendChild(memo);
    }
    drawWave();
    return;
  }

  requestAnimationFrame(onFrame);
  talk();
})();
