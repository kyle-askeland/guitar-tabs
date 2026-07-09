import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ScanCommand, GetCommand, PutCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';
import { makeHandler } from '../src/index.mjs';

// In-memory DynamoDB double: enough Scan/Get/Put/Delete for the handler's usage.
function fakeDb() {
  const items = new Map();
  return {
    items,
    send(cmd) {
      const { input } = cmd;
      if (cmd instanceof ScanCommand) {
        const all = [...items.values()];
        if (input.Select === 'COUNT') return { Count: all.length };
        return { Items: all };
      }
      if (cmd instanceof GetCommand) return { Item: items.get(input.Key.PK) };
      if (cmd instanceof PutCommand) { items.set(input.Item.PK, input.Item); return {}; }
      if (cmd instanceof DeleteCommand) { items.delete(input.Key.PK); return {}; }
      throw new Error('unexpected command');
    },
  };
}

const event = (method, { id, token, body } = {}) => ({
  requestContext: { http: { method } },
  pathParameters: id ? { id } : undefined,
  headers: token ? { 'x-owner-token': token } : {},
  body: body === undefined ? undefined : JSON.stringify(body),
});

const parse = (res) => JSON.parse(res.body);

test('POST creates a song, GET list and GET by id return it', async () => {
  const handler = makeHandler(fakeDb());
  const created = await handler(event('POST', { token: 't1', body: { title: 'Blackbird', artist: 'The Beatles' } }));
  assert.equal(created.statusCode, 201);
  const song = parse(created);
  assert.ok(song.songId);
  assert.deepEqual(song.tuning, ['E', 'A', 'D', 'G', 'B', 'E']);
  assert.equal(song.mine, true);

  const list = parse(await handler(event('GET', { token: 't1' })));
  assert.equal(list.length, 1);
  assert.equal(list[0].title, 'Blackbird');
  assert.equal(list[0].mine, true);
  assert.equal(list[0].ownerTokenHash, undefined);
  assert.equal(list[0].sections, undefined);

  const full = parse(await handler(event('GET', { id: song.songId })));
  assert.deepEqual(full.sections, []);
  assert.equal(full.mine, false); // no token sent
});

test('POST without token is 401; invalid body is 400', async () => {
  const handler = makeHandler(fakeDb());
  assert.equal((await handler(event('POST', { body: { title: 'x' } }))).statusCode, 401);
  assert.equal((await handler(event('POST', { token: 't', body: { title: '' } }))).statusCode, 400);
  assert.equal((await handler(event('POST', { token: 't', body: { title: 'x', sections: [{}] } }))).statusCode, 400);
});

test('PUT updates for owner, 403 for others, 404 for missing', async () => {
  const handler = makeHandler(fakeDb());
  const song = parse(await handler(event('POST', { token: 'owner', body: { title: 'v1' } })));
  const update = { title: 'v2', sections: [{ name: 'Intro', lines: [{ cells: [], barlines: [], length: 40 }] }] };

  const denied = await handler(event('PUT', { id: song.songId, token: 'intruder', body: update }));
  assert.equal(denied.statusCode, 403);

  const ok = parse(await handler(event('PUT', { id: song.songId, token: 'owner', body: update })));
  assert.equal(ok.title, 'v2');
  assert.equal(ok.sections.length, 1);
  assert.equal(ok.createdAt, song.createdAt);

  assert.equal((await handler(event('PUT', { id: 'nope', token: 'owner', body: update }))).statusCode, 404);
});

test('DELETE is owner-only and permanent', async () => {
  const db = fakeDb();
  const handler = makeHandler(db);
  const song = parse(await handler(event('POST', { token: 'owner', body: { title: 'doomed' } })));

  assert.equal((await handler(event('DELETE', { id: song.songId, token: 'other' }))).statusCode, 403);
  assert.equal((await handler(event('DELETE', { id: song.songId, token: 'owner' }))).statusCode, 200);
  assert.equal(db.items.size, 0);
  assert.equal((await handler(event('GET', { id: song.songId }))).statusCode, 404);
});

test('caps: body size and song count', async () => {
  const db = fakeDb();
  const handler = makeHandler(db);
  const big = await handler({ ...event('POST', { token: 't' }), body: 'x'.repeat(129 * 1024) });
  assert.equal(big.statusCode, 413);

  for (let i = 0; i < 500; i++) db.items.set(`SONG#${i}`, { PK: `SONG#${i}` });
  const full = await handler(event('POST', { token: 't', body: { title: 'one too many' } }));
  assert.equal(full.statusCode, 409);
});
