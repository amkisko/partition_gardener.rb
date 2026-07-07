# Contributing guidelines

Thank you for your interest in contributing. We value learning over perfection but require rigor and responsibility.

## The golden rule of automation

We welcome the use of AI and automation tools to reduce toil, but you must strictly adhere to the following:

1. You are the author. You act as the responsible agent for any code you submit. You must review, debug, and understand every line.

2. Manage cognitive load. Do not submit massive, unreviewed automated dumps. Respect the reviewers' time by annotating complex logic.

3. Security. Never feed project secrets or private context into public AI models.

## How to contribute

### Reporting issues

- Verify accuracy. Before posting, verify your information. Avoid generalizations.
- Use structured inputs. Use our issue templates to provide clear goals, constraints, and reproduction steps. This helps us understand the context immediately.

### Pull request process

- Scope. Keep pull requests focused on a single goal.
- Context. Explain why the change is necessary. Transparency builds trust.
- Testing. Run all smoke tests and regression checks locally. We prioritize safety first.

For this repository, run `make lint && make test` before opening a pull request when the change touches executable code. Integration specs need PostgreSQL; see [spec/README.md](spec/README.md).

### Review process

- We encourage productive friction. Expect questions about your approach.
- If a reviewer suggests a change, view it as mutual aid, not criticism.
