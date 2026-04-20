from pathlib import Path

content = """# CODEX_PROMPTS_CTS

This file contains a practical prompt sequence for using Codex in VS Code to understand the CTS repository and get to the point where you can build a CTS-inspired simulator for synthetic cryo-ET tilt-series generation.

## Important scope reminder

For now, the goal is only:

- understand the synthetic-data / tilt-series simulation part of CTS
- identify how CTS generates randomized simplified cellular-like environments
- identify the exact simulation pipeline and control parameters
- get enough understanding to build a smaller CTS-inspired simulator

Not in scope for now:

- segmentation training workflows
- the full AI optimization loop for the larger project
- generalized MLOps / training architecture

---

## 0. One-time setup prompt

```text
You are helping me understand and reimplement the synthetic data / tilt-series simulation part of the CTS method, mainly following:
1) Purnell et al. 2025 paper
2) its supplementary information
3) the earlier 2023 CTS paper when needed

Scope for now:
- only the synthetic data and tilt-series simulation part
- not deep-learning training
- not the full research plan
- goal is to understand the repo well enough to build my own simulator for this project

Important constraints:
- be concrete and code-oriented
- distinguish clearly between what the existing CTS repo actually does and what you are inferring
- do not give vague summaries when code inspection can answer the question
- when you mention a file/function, include its exact path
- when you infer behavior from the papers rather than the code, label it explicitly as “paper-derived”
- if the repo behavior differs from the papers, say so explicitly

My immediate deliverables:
A) a precise map of the CTS pipeline in code
B) identification of all parameters relevant to tilt-series simulation
C) a minimal reproducible run path from structure inputs to synthetic tomogram
D) a reimplementation plan for a smaller custom simulator inspired by CTS