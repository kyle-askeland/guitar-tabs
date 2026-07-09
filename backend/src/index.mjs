import { createHash, randomUUID } from 'node:crypto';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import {
  DynamoDBDocumentClient, ScanCommand, GetCommand, PutCommand, DeleteCommand,
} from '@aws-sdk/lib-dynamodb';

const TABLE = process.env.TABLE_NAME ?? 'guitar-tabs';
const MAX_BODY_BYTES = 128 * 1024;
const MAX_SONGS = 500;
const MAX_SECTIONS = 50;
const MAX_LINES_PER_SECTION = 100;

const sha256 = (s) => createHash('sha256').update(s).digest('hex');
const json = (statusCode, body) => ({
  statusCode,
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify(body),
});
const error = (statusCode, message) => json(statusCode, { message });

// Validates the client-supplied song document; returns an error message or null.
function invalidSong(song) {
  if (typeof song !== 'object' || song === null) return 'body must be a JSON object';
  if (typeof song.title !== 'string' || !song.title.trim() || song.title.length > 200) {
    return 'title is required (string, 1-200 chars)';
  }
  const sections = song.sections ?? [];
  if (!Array.isArray(sections) || sections.length > MAX_SECTIONS) {
    return `sections must be an array of at most ${MAX_SECTIONS}`;
  }
  for (const s of sections) {
    if (!Array.isArray(s?.lines) || s.lines.length > MAX_LINES_PER_SECTION) {
      return `each section needs a lines array of at most ${MAX_LINES_PER_SECTION}`;
    }
  }
  return null;
}

function parseBody(event) {
  const raw = event.isBase64Encoded ? Buffer.from(event.body ?? '', 'base64').toString() : event.body ?? '';
  if (Buffer.byteLength(raw) > MAX_BODY_BYTES) return { error: error(413, 'request body too large') };
  try {
    return { song: JSON.parse(raw) };
  } catch {
    return { error: error(400, 'invalid JSON') };
  }
}

// Strips server-managed fields from GET responses and adds `mine` for the caller's token.
const publicSong = (item, tokenHash) => ({ ...item.data, mine: item.ownerTokenHash === tokenHash });

export function makeHandler(db) {
  return async (event) => {
    const method = event.requestContext.http.method;
    const id = event.pathParameters?.id;
    const token = event.headers?.['x-owner-token'];
    const tokenHash = token ? sha256(token) : null;

    if (!id) {
      if (method === 'GET') {
        const { Items = [] } = await db.send(new ScanCommand({
          TableName: TABLE,
          ProjectionExpression: 'songId, title, artist, updatedAt, ownerTokenHash',
        }));
        Items.sort((a, b) => (a.updatedAt < b.updatedAt ? 1 : -1));
        return json(200, Items.map(({ ownerTokenHash, ...s }) => ({ ...s, mine: ownerTokenHash === tokenHash })));
      }
      if (method === 'POST') {
        if (!token) return error(401, 'x-owner-token header required');
        const { song, error: err } = parseBody(event);
        if (err) return err;
        const invalid = invalidSong(song);
        if (invalid) return error(400, invalid);
        const { Count } = await db.send(new ScanCommand({ TableName: TABLE, Select: 'COUNT' }));
        if (Count >= MAX_SONGS) return error(409, `song limit reached (${MAX_SONGS})`);
        const now = new Date().toISOString();
        const doc = {
          songId: randomUUID(),
          title: song.title.trim(),
          artist: song.artist ?? '',
          tuning: song.tuning ?? ['E', 'A', 'D', 'G', 'B', 'E'],
          capo: song.capo ?? 0,
          createdAt: now,
          updatedAt: now,
          sections: song.sections ?? [],
        };
        await db.send(new PutCommand({
          TableName: TABLE,
          Item: {
            PK: `SONG#${doc.songId}`, SK: 'META',
            songId: doc.songId, title: doc.title, artist: doc.artist, updatedAt: now,
            ownerTokenHash: tokenHash, data: doc,
          },
        }));
        return json(201, { ...doc, mine: true });
      }
      return error(405, 'method not allowed');
    }

    const key = { PK: `SONG#${id}`, SK: 'META' };
    const { Item } = await db.send(new GetCommand({ TableName: TABLE, Key: key }));
    if (!Item) return error(404, 'song not found');

    if (method === 'GET') return json(200, publicSong(Item, tokenHash));

    if (Item.ownerTokenHash !== tokenHash) return error(403, 'not the owner of this song');

    if (method === 'PUT') {
      const { song, error: err } = parseBody(event);
      if (err) return err;
      const invalid = invalidSong(song);
      if (invalid) return error(400, invalid);
      const doc = {
        ...Item.data,
        title: song.title.trim(),
        artist: song.artist ?? '',
        tuning: song.tuning ?? Item.data.tuning,
        capo: song.capo ?? Item.data.capo,
        sections: song.sections ?? [],
        updatedAt: new Date().toISOString(),
      };
      await db.send(new PutCommand({
        TableName: TABLE,
        Item: { ...Item, title: doc.title, artist: doc.artist, updatedAt: doc.updatedAt, data: doc },
      }));
      return json(200, { ...doc, mine: true });
    }

    if (method === 'DELETE') {
      await db.send(new DeleteCommand({ TableName: TABLE, Key: key }));
      return json(200, { deleted: id });
    }

    return error(405, 'method not allowed');
  };
}

export const handler = makeHandler(DynamoDBDocumentClient.from(new DynamoDBClient({})));
