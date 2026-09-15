import { strict as assert } from "node:assert";
import test from "node:test";
import { tryAcquire, release, currentlyActive, resetConcurrency } from "../concurrency.js";

test("acquire succeeds up to the limit, then refuses", async () => {
  resetConcurrency();
  assert.equal(await tryAcquire(2), true);
  assert.equal(await tryAcquire(2), true);
  assert.equal(await tryAcquire(2), false, "the third caller is over the limit");
  assert.equal(await currentlyActive(), 2);
});

test("a released slot can be acquired again", async () => {
  resetConcurrency();
  assert.equal(await tryAcquire(1), true);
  assert.equal(await tryAcquire(1), false);

  await release();
  assert.equal(await currentlyActive(), 0);
  assert.equal(await tryAcquire(1), true);
});

test("release never goes negative, however many times it is called", async () => {
  resetConcurrency();
  await release();
  await release();
  assert.equal(await currentlyActive(), 0);
});
