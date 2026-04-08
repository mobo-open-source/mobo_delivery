# Contributing to Mobo Delivery

Thank you for considering a contribution! Please read these guidelines before opening an issue or pull request.

## Getting Started

1. Fork the repository and clone your fork.
2. Follow the setup steps in [README.md](README.md) to configure your local environment.
3. Create a new branch from `main` for your change:
   ```bash
   git checkout -b feat/your-feature-name
   ```

## Code Standards

- **No debug output** — `print()`, `debugPrint()`, and `log()` calls must not appear in committed code. Use Flutter's built-in error handling and surface errors to the UI where appropriate.
- **No hardcoded secrets** — API keys, passwords, and tokens must come from `.env` or `local.properties`. Never commit sensitive values.
- **Doc comments** — All public classes, methods, and widgets must have a `///` doc comment.
- **Linter** — Run `flutter analyze` before opening a PR. Zero errors and zero warnings are required; info-level hints should be minimised.
- **Formatter** — Run `dart format .` before committing.

## Secrets & Environment Files

The following files are gitignored and must **never** be committed:

| File | Purpose |
|---|---|
| `.env` | AES encryption key for map token storage |
| `android/local.properties` | SDK paths + Google Maps API key |
| `android/key.properties` | Release signing credentials |
| `android/upload-keystore.jks` | Release signing keystore |

Use the `.example` counterparts as templates.

## Pull Request Process

1. Ensure `flutter analyze` and `flutter test` pass with no errors.
2. Keep PRs focused — one feature or bug fix per PR.
3. Write a clear PR description explaining *what* changed and *why*.
4. Reference any related issues with `Fixes #issue_number`.

## Reporting Issues

- Search existing issues before opening a new one.
- Include your Flutter version (`flutter --version`), device/emulator details, and steps to reproduce.

## License

By contributing, you agree that your contributions will be licensed under the same [Apache 2.0 License](LICENSE) that covers this project.
