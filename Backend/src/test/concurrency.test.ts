import { strict as assert } from "node:assert";
import test from "node:test";
import { tryAcquire, release, currentlyActive, resetConcurrency } from "../concurrency.js";

test("acquire succeeds up to the limit, then refuses", () => {
  resetConcurrency();
  assert.equal(tryAcquire(2), true);
  assert.equal(tryAcquire(2), true);
  assert.equal(tryAcquire(2), false, "the third caller is over the limit");
  assert.equal(currentlyActive(), 2);
});

test("a released slot can be acquired again", () => {
  resetConcurrency();
  assert.equal(tryAcquire(1), true);
  assert.equal(tryAcquire(1), false);

  release();
  assert.equal(currentlyActive(), 0);
  assert.equal(tryAcquire(1), true);
});

test("release never goes negative, however many times it is called", () => {
  resetConcurrency();
  release();
  release();
  assert.equal(currentlyActive(), 0);
});
