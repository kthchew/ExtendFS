# Security Policy

## Supported Versions

ExtendFS has security support provided you are on the latest public release version of macOS within some major version equal to or greater than macOS Sequoia (15).

As of right now, the latest ExtendFS supports any major version of macOS beginning with macOS Sequoia 15.6. There are no versions of ExtendFS that run on any versions of macOS older than macOS Sequoia.

## Reporting a Vulnerability

To report a vulnerability privately, go to the "Security and quality" tab (https://github.com/kthchew/ExtendFS/security) and submit your report. Don't open security-related reports in the Issues tab, as those reports are automatically made public.

Only report an issue privately if you believe it is security-related. For example, issues including, but not limited to:

* The ability to execute arbitrary code in the ExtendFS extension process
* The ability to read or write arbitrary memory in the ExtendFS extension process
* The ability to exfiltrate data by mounting a malicious volume
* An issue that might theoretically lead to one of the above if it were chained with another issue

If the issue is not security-related, such as a non-exploitable crash or a general bug, please file a bug report using the instructions at the [general support page](https://apps.kpchew.com/extendfs/support) instead. If you believe the issue lies in macOS (e.g. a security-related issue in FSKit) and not in ExtendFS, do not report the issue to me. Instead, [report the issue to Apple](https://security.apple.com/).

When reporting a vulnerability, please include the following information:
* A general description of the issue
* A list of steps to reproduce the issue
* What behavior you expected
* What behavior actually happened
* The versions of macOS and ExtendFS
* Supporting files, such as a sample disk image that reproduces the issue

Your report will be disclosed publicly about one month after I release a version of ExtendFS that fixes the issue, along with credit to you for identifying the bug. You will be credited via your GitHub username. If you want to be credited under another name or remain anonymous, please indicate this in your report. There are no other incentives (monetary or otherwise) for reporting issues.

If the report is not valid or does not appear to be security-related, I will let you know and publicly disclose it about one week after notifying you.
