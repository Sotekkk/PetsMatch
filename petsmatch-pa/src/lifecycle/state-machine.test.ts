import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  STATUSES,
  TRANSITIONS,
  canTransition,
  assertTransition,
  isLocked,
  InvalidTransitionError,
} from './state-machine.js';

test('toute cible de transition est un statut connu', () => {
  for (const [from, targets] of Object.entries(TRANSITIONS)) {
    assert.ok(STATUSES.includes(from as (typeof STATUSES)[number]), `statut inconnu : ${from}`);
    for (const to of targets) {
      assert.ok(STATUSES.includes(to), `cible inconnue depuis ${from} : ${to}`);
    }
  }
});

test('chemin nominal brouillon → payee', () => {
  const path = [
    'brouillon',
    'validee',
    'emise',
    'transmise',
    'mise_a_disposition',
    'acceptee',
    'payee',
  ] as const;
  for (let i = 0; i < path.length - 1; i++) {
    assert.ok(canTransition(path[i]!, path[i + 1]!), `${path[i]} → ${path[i + 1]} devrait être permis`);
  }
});

test('transition interdite → InvalidTransitionError lisible', () => {
  assert.equal(canTransition('brouillon', 'payee'), false);
  assert.throws(
    () => assertTransition('brouillon', 'payee'),
    (e: unknown) => e instanceof InvalidTransitionError && /Transition interdite/.test((e as Error).message),
  );
});

test('annulee est terminal', () => {
  assert.deepEqual(TRANSITIONS.annulee, []);
});

test('le contenu est figé dès la sortie de brouillon', () => {
  assert.equal(isLocked('brouillon'), false);
  assert.equal(isLocked('validee'), true);
  assert.equal(isLocked('emise'), true);
});
