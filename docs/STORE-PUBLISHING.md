# Store publishing through JetKVM

Owner instruction, November 7, 2026: use JetKVM for Windows and Linux store
account access and publishing. Build, package and test on Orion. The Mac handles
source, orchestration and the observed store websites. Keep GitHub Actions and
unapproved hosted builds disabled.

JetKVM controls the currently cabled Mac. That Mac can access publishing portals
for either operating system; the store submission website does not need to run
on the same OS as the application being uploaded. JetKVM does not supply a
publisher account, app identity, installation package or store certification.

## Microsoft Store

Use the owner's existing Microsoft identity and actual Partner Center or Store
developer session. Before input, follow the live guide in `jetkvm-agent`:
verify the physical target, current screen and identity, take the exclusive input
lease, perform bounded actions, verify the result and release the lease.
Use saved credentials, native AutoFill and associated verification routes;
never record passwords or verification codes in this repository.

After developer enrollment is verified, reserve the actual product and obtain
its exact package identity and publisher details. Do not invent those values.
The chosen audio installation model determines whether the complete release
uses an MSIX controller plus a valid separate audio-component delivery route,
or an eligible traditional EXE/MSI installer.

An approved MSIX/AppX Store package is signed by Microsoft during publication;
a separately purchased CA certificate is not a blanket prerequisite for that
route. EXE/MSI installers need the publisher's own valid Authenticode signature.
Audio-component signing/installation remains a separate requirement. See
[Microsoft's package requirements](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/app-package-requirements)
and the [platform delivery plan](WINDOWS-LINUX.md).

Build the selected package on Orion, verify installation and the actual system
EQ, then use JetKVM to complete the truthful listing, upload the exact tested
artifact and submit it. Reconcile any uncertain upload or submission from the
portal's actual state before retrying.

## Linux stores

There is no single Linux store submission. Snap Store and Flathub have different
packaging, account and review procedures. The owner was asked which route to
prepare; no Linux storefront is recorded as owner-selected yet.

**Snap Store:** build and test the actual `.snap` on Orion, reuse or establish the
owner's Ubuntu publishing identity, register the real snap name, and configure
its listing and release channel through JetKVM. Snapcraft supports uploading an
already built package separately from releasing it. Do not select remote/cloud
builds or turn an upload into an unintended stable release. See
[Canonical's release procedure](https://documentation.ubuntu.com/snapcraft/9.0/how-to/publishing/manage-revisions-and-releases/).

**Flathub:** research and local qualification can be prepared on Orion, but its
current rules prohibit AI-authored manifests and agent-automated submission PRs
or submission/review text. Submission therefore requires a human-maintained
manifest and human interaction with Flathub. Generated application material
also needs the disclosure required by its policy. JetKVM is not a way around
those rules. See the [current requirements](https://docs.flathub.org/docs/for-app-authors/requirements#generative-ai-policy)
and [submission procedure](https://docs.flathub.org/docs/for-app-authors/submission).
Do not enable Actions or request hosted builds under the current compute policy.

Both routes still require real Linux desktop/audio qualification and suitable
packaging. The current Ubuntu WSL2/offscreen editor checks do not establish
PipeWire routing, sandbox permissions or physical-device recovery.

## Observed access and release status — November 7

- JetKVM health, physical device identity, USB configuration, video and US
  keyboard layout were verified on the cabled Mac. A dedicated Safari Personal
  publishing tab was used; existing unrelated tabs were preserved.
- Partner Center redirected to Microsoft's actual login service. The owner
  identity was recognized and Microsoft offered email-code sign-in. No code was
  requested, no code was copied, and no signed-in publisher identity or developer
  enrollment was verified. The installed verification configuration has no
  Microsoft-specific route. This is passwordless sign-in readiness, not proof of
  a missing account or password.
- The encrypted catalog had no Snapcraft, Ubuntu or Flathub match. Its separate
  Apple Passwords/native AutoFill source is not included in that scan, so this
  does not prove that no saved account exists.
- Physical input leases were released. No product name was reserved, package
  uploaded, account created, payment made, hosted build started or app submitted.
- The current deliverables remain working desktop preset-editor previews.
  System audio integration, smooth live changes, device lifecycle handling and
  installation qualification are still required for the intended system EQ.

Use the [verified desktop UI build](reports/ORION-DESKTOP-UI-2026-11-07.md) as the
starting point. Store access and screen control do not replace those release
requirements.
