import { describe, it, expect } from "vitest";

const accounts = simnet.getAccounts();
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;

describe("CurateChain + Bitcoin Trust Score Tests", () => {

  // ===========================
  // General Setup
  // ===========================
  it("simnet is initialized", () => {
    expect(simnet.blockHeight).toBeDefined();
  });

  // ===========================
  // CurateChain Tests
  // ===========================
  it("submits a new content item successfully", () => {
    const { result } = simnet.call(
      "curate-chain",
      "contribute-item",
      ["\"Hello World\"","\"https://example.com\"","\"Technology\""],
      wallet1
    );
    expect(result).toBeOk();
  });

  it("prevents invalid content submissions", () => {
    const { result } = simnet.call(
      "curate-chain",
      "contribute-item",
      ["\"\"","\"http\"","\"UnknownTopic\""],
      wallet1
    );
    expect(result).toBeErr(); // empty headline, short hyperlink, invalid topic
  });

  it("prevents self-flagging of content", () => {
    const { result } = simnet.call(
      "curate-chain",
      "flag-item",
      ["u1"],
      wallet1
    );
    expect(result).toBeErr();
  });

  it("prevents appraisal with invalid value", () => {
    const { result } = simnet.call(
      "curate-chain",
      "appraise-item",
      ["u1", "2"], // must be 1 or -1
      wallet2
    );
    expect(result).toBeErr();
  });

  it("prevents reward with insufficient balance", () => {
    const { result } = simnet.call(
      "curate-chain",
      "reward-originator",
      ["u1", "1000000"],
      wallet2
    );
    expect(result).toBeErr();
  });

  // ===========================
  // Bitcoin Trust Score Tests
  // ===========================
  it("creates a new identity", () => {
    const { result } = simnet.call(
      "trust-score",
      "create-identity",
      ["\"did:stackstest:wallet1\""],
      wallet1
    );
    expect(result).toBeOk();
  });

  it("prevents creating duplicate identity", () => {
    const { result } = simnet.call(
      "trust-score",
      "create-identity",
      ["\"did:stackstest:wallet1\""],
      wallet1
    );
    expect(result).toBeErr();
  });

  it("prevents invalid reputation action", () => {
    const { result } = simnet.call(
      "trust-score",
      "update-reputation-score",
      ["\"invalid-action\""],
      wallet1
    );
    expect(result).toBeErr();
  });

  it("applies decay only after period elapsed", () => {
    const { result } = simnet.call(
      "trust-score",
      "decay-reputation",
      [],
      wallet1
    );
    expect(result).toBeErr(); // ERR-INVALID-PARAMETERS
  });

  it("caps reputation at MAX-REPUTATION-SCORE", () => {
    // simulate actions to reach MAX
    simnet.call("trust-score", "update-reputation-score", ["\"contract-fulfillment\""], wallet1);
    simnet.call("trust-score", "update-reputation-score", ["\"contract-fulfillment\""], wallet1);
    const { result } = simnet.call("trust-score", "update-reputation-score", ["\"contract-fulfillment\""], wallet1);
    expect(result).toBeOk(); // capped at MAX
  });

  it("prevents actions if identity inactive", () => {
    simnet.call("trust-score", "update-identity-status", [false], wallet1);
    const { result } = simnet.call(
      "trust-score",
      "update-reputation-score",
      ["\"content-creation\""],
      wallet1
    );
    expect(result).toBeErr(); // ERR-UNAUTHORIZED
  });

});
