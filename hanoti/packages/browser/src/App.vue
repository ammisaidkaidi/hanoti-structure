<script setup lang="ts">
import { onMounted, ref } from 'vue';
import { greetingRequestSchema } from '@app/common';
import { getHealth, sendGreeting } from './api';

const health = ref<'checking' | 'online' | 'offline'>('checking');
const checkedAt = ref('');
const name = ref('');
const busy = ref(false);
const message = ref('');
const error = ref('');
const packages = [
  {
    code: '01',
    name: 'Common',
    path: 'packages/common',
    description: 'One source of truth. Shared types and runtime validation across the stack.',
    tags: ['TypeScript', 'Zod'],
    symbol: '◇',
  },
  {
    code: '02',
    name: 'Browser',
    path: 'packages/browser',
    description: 'A fast, reactive interface with type-safe API calls and utility-first styling.',
    tags: ['Vue 3', 'Vite', 'Tailwind CSS'],
    symbol: '▣',
  },
  {
    code: '03',
    name: 'Server',
    path: 'packages/server',
    description: 'A focused API with validated requests, security headers and hot reloading.',
    tags: ['Express', 'Node.js', 'tsx'],
    symbol: '⌘',
  },
  {
    code: '04',
    name: 'Data',
    path: 'data',
    description: 'A dedicated home for SQL migrations, development seeds and private assets.',
    tags: ['SQL assets', 'Server-only'],
    symbol: '▤',
  },
];
async function checkHealth() {
  health.value = 'checking';
  try {
    const response = await getHealth();
    health.value = 'online';
    checkedAt.value = new Date(response.timestamp).toLocaleTimeString([], {
      hour: '2-digit',
      minute: '2-digit',
    });
  } catch {
    health.value = 'offline';
  }
}
async function submit() {
  message.value = '';
  error.value = '';
  const parsed = greetingRequestSchema.safeParse({ name: name.value });
  if (!parsed.success) {
    error.value = parsed.error.issues[0]?.message ?? 'Check your name.';
    return;
  }
  busy.value = true;
  try {
    message.value = (await sendGreeting(parsed.data)).message;
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : 'Unable to reach the API.';
  } finally {
    busy.value = false;
  }
}
onMounted(checkHealth);
</script>

<template>
  <div class="min-h-screen lg:grid lg:grid-cols-[232px_1fr]">
    <aside class="flex flex-col bg-ink px-7 py-7 text-white lg:sticky lg:top-0 lg:h-screen">
      <a
        href="#overview"
        class="flex items-center gap-3 text-xl font-semibold tracking-tight"
        aria-label="Hanouti home"
      >
        <span
          class="flex h-9 w-9 items-center justify-center rounded-xl bg-[#b8e9b1] font-mono text-xl text-ink"
          >h.</span
        >
        hanouti<span class="text-[#b8e9b1]">.</span>
      </a>
      <div
        class="mt-12 hidden text-[10px] font-semibold uppercase tracking-[0.2em] text-white/40 lg:block"
      >
        Your workspace
      </div>
      <nav class="mt-5 flex gap-2 lg:flex-col" aria-label="Workspace navigation">
        <a
          href="#overview"
          class="rounded-lg bg-white/10 px-4 py-3 text-sm font-medium text-[#c9edc3]"
          >◫ <span class="ml-2">Overview</span></a
        >
        <a
          href="#architecture"
          class="rounded-lg px-4 py-3 text-sm text-white/60 transition hover:bg-white/5 hover:text-white"
          >◇ <span class="ml-2">Architecture</span></a
        >
        <a
          href="#playground"
          class="rounded-lg px-4 py-3 text-sm text-white/60 transition hover:bg-white/5 hover:text-white"
          >⌁ <span class="ml-2">API playground</span></a
        >
      </nav>
      <div class="mt-auto hidden border-t border-white/10 pt-6 lg:block">
        <p class="font-mono text-xs text-[#c9edc3]">pnpm workspace</p>
        <p class="mt-2 text-xs leading-6 text-white/40">
          Four packages.<br />One connected foundation.
        </p>
        <div
          class="mt-5 flex items-center justify-between text-[10px] uppercase tracking-widest text-white/30"
        >
          <span>Starter edition</span><span>v0.1.0</span>
        </div>
      </div>
    </aside>

    <div class="min-w-0">
      <header
        class="flex items-center justify-between border-b border-black/[0.07] px-6 py-5 lg:px-12"
      >
        <div class="text-xs text-gray-500">
          Workspace <span class="mx-3 text-gray-300">/</span> <span class="text-ink">Overview</span>
        </div>
        <span
          class="rounded-full border border-black/10 bg-white px-3 py-1 font-mono text-[10px] text-gray-500"
          >FULL-STACK STARTER</span
        >
      </header>
      <main id="overview" class="mx-auto max-w-[1320px] px-6 py-10 lg:px-12 lg:py-12">
        <div class="flex flex-wrap items-start justify-between gap-5">
          <div>
            <p class="text-[10px] font-semibold uppercase tracking-[0.22em] text-leaf">
              A foundation for what’s next
            </p>
            <h1 class="mt-3 text-4xl font-medium tracking-[-0.045em] sm:text-5xl">
              Make yourself at home.
            </h1>
            <p class="mt-4 max-w-xl text-sm leading-7 text-gray-500">
              Your full-stack workspace, connected from day one.<br class="hidden sm:block" />
              Less setup. More room to build something great.
            </p>
          </div>
          <button
            :disabled="health === 'checking'"
            class="flex items-center gap-2 rounded-full border border-black/10 bg-white px-4 py-2.5 text-xs disabled:opacity-60"
            title="Refresh API health"
            @click="checkHealth"
          >
            <span
              class="h-1.5 w-1.5 rounded-full"
              :class="
                health === 'online'
                  ? 'bg-leaf'
                  : health === 'offline'
                    ? 'bg-amber-500'
                    : 'animate-pulse bg-gray-400'
              "
            ></span
            >{{
              health === 'online'
                ? 'API connected'
                : health === 'offline'
                  ? 'API offline · Retry'
                  : 'Connecting…'
            }}<span class="ml-1 text-gray-400">↻</span>
          </button>
        </div>

        <section
          class="relative mt-9 overflow-hidden rounded-2xl bg-[#e7eddf] p-7 sm:p-8"
          aria-label="Quick start"
        >
          <div
            class="pointer-events-none absolute -right-6 -top-14 h-64 w-64 rounded-full border-[35px] border-[#d5dfca]/60"
            aria-hidden="true"
          ></div>
          <div class="relative flex flex-wrap items-center justify-between gap-6">
            <div>
              <span
                class="rounded-md bg-white/60 px-2 py-1 text-[9px] font-bold uppercase tracking-widest text-leaf"
                >Ready when you are</span
              >
              <h2 class="mt-4 text-2xl font-medium tracking-tight">
                One command. The whole stack.
              </h2>
              <p class="mt-2 text-xs leading-6 text-gray-600">
                Run from the repository root to start all workspace development processes.
              </p>
            </div>
            <div class="min-w-[235px] rounded-xl bg-ink px-6 py-5 text-white shadow-lg">
              <div class="mb-3 flex gap-1.5" aria-hidden="true">
                <i class="h-1.5 w-1.5 rounded-full bg-white/20"></i
                ><i class="h-1.5 w-1.5 rounded-full bg-white/20"></i
                ><i class="h-1.5 w-1.5 rounded-full bg-white/20"></i>
              </div>
              <code class="text-sm"><span class="mr-3 text-[#a4d99b]">$</span>pnpm dev</code>
            </div>
          </div>
        </section>

        <section id="architecture" class="scroll-mt-8 pt-10">
          <div class="mb-5 flex items-center justify-between">
            <h2 class="text-lg font-medium tracking-tight">Built to work together</h2>
            <span class="font-mono text-[10px] uppercase tracking-widest text-gray-400"
              >04 workspace packages</span
            >
          </div>
          <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <article
              v-for="pkg in packages"
              :key="pkg.name"
              class="rounded-xl border border-black/[0.08] bg-white p-5 transition hover:border-leaf/30"
            >
              <div class="flex items-center justify-between">
                <span
                  class="flex h-10 w-10 items-center justify-center rounded-lg bg-canvas text-2xl text-leaf"
                  aria-hidden="true"
                  >{{ pkg.symbol }}</span
                ><span class="font-mono text-[10px] text-gray-300">{{ pkg.code }}</span>
              </div>
              <h3 class="mt-5 text-base font-semibold">{{ pkg.name }}</h3>
              <p class="mt-1 font-mono text-[10px] text-leaf">{{ pkg.path }}</p>
              <p class="mt-4 min-h-[66px] text-xs leading-[1.8] text-gray-500">
                {{ pkg.description }}
              </p>
              <div class="mt-5 flex flex-wrap gap-1.5">
                <span
                  v-for="tag in pkg.tags"
                  :key="tag"
                  class="rounded border border-black/5 bg-canvas px-2 py-1 text-[9px] text-gray-500"
                  >{{ tag }}</span
                >
              </div>
            </article>
          </div>
        </section>

        <section
          id="playground"
          class="mt-8 grid scroll-mt-8 overflow-hidden rounded-xl border border-black/[0.08] bg-white md:grid-cols-[1fr_1.1fr]"
        >
          <div class="p-6 sm:p-7">
            <div class="flex items-center gap-2">
              <span class="h-1.5 w-1.5 rounded-full bg-leaf"></span>
              <p class="text-[10px] font-semibold uppercase tracking-widest text-leaf">
                End-to-end, by design
              </p>
            </div>
            <h2 class="mt-3 text-xl font-medium tracking-tight">Say hello to your API.</h2>
            <p class="mt-3 max-w-sm text-xs leading-6 text-gray-500">
              A real request from Vue to Express. Validated with your shared Zod schema, with a
              greeting from a server-side data asset.
            </p>
            <p class="mt-5 font-mono text-[10px] text-gray-400">
              <span class="mr-2 text-leaf">POST</span> /api/greetings
            </p>
          </div>
          <form
            class="flex flex-col justify-center border-t border-black/[0.06] bg-[#fbfcf9] p-6 sm:p-7 md:border-l md:border-t-0"
            @submit.prevent="submit"
          >
            <label for="name" class="mb-2 text-xs font-medium">What should we call you?</label>
            <div class="flex flex-wrap gap-2">
              <input
                id="name"
                v-model="name"
                autocomplete="given-name"
                placeholder="Your name"
                maxlength="80"
                :aria-invalid="!!error"
                aria-describedby="greeting-result"
                class="min-w-0 flex-1 rounded-lg border border-black/15 bg-white px-4 py-3 text-sm placeholder:text-gray-400"
              /><button
                type="submit"
                :disabled="busy"
                class="rounded-lg bg-ink px-5 py-3 text-xs font-medium text-white transition hover:bg-leaf disabled:opacity-50"
              >
                {{ busy ? 'Sending…' : 'Send greeting' }}
                <span class="ml-2" aria-hidden="true">↗</span>
              </button>
            </div>
            <p
              id="greeting-result"
              role="status"
              class="mt-3 min-h-8 text-xs leading-5"
              :class="error ? 'text-red-700' : message ? 'text-leaf' : 'text-gray-400'"
            >
              {{ error || message || 'Shared types. Runtime validation. A connected stack.' }}
            </p>
          </form>
        </section>
        <footer
          class="mt-8 flex flex-wrap items-center justify-between gap-3 border-t border-black/[0.07] pt-5 text-[10px] text-gray-400"
        >
          <span>Hanouti <span class="mx-2">/</span> A little structure. A lot of possibility.</span
          ><span>{{
            health === 'online'
              ? `API checked at ${checkedAt}`
              : 'Start the server to connect the API'
          }}</span>
        </footer>
      </main>
    </div>
  </div>
</template>
