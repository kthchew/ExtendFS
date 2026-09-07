# Bug Reports, Requests, and Questions

If you just have a general question, you can ask in the [discussions tab](https://github.com/kthchew/ExtendFS/discussions).

You can submit bug reports or requests in the [issues tab](https://github.com/kthchew/ExtendFS/issues). Before you do so, please update to the latest macOS (at the very least, the latest version for the major macOS release you are on) that you can, as some bugs might be FSKit bugs.

Note that issues you open are public, which includes any attachments you send. Please don't send private data unless requested and it is absolutely necessary to troubleshoot an issue. By default, information like directory names and contents are not visible in the logs.

While I try to respond in a timely manner, please allow a reasonable amount of time for a response. There are no SLAs, and I do not prioritize issues any differently based on whether you downloaded ExtendFS from the App Store or from GitHub.

## Volumes not mounting

If the issue involves a volume not mounting, report the issue as a bug in the [issues tab](https://github.com/kthchew/ExtendFS/issues).

For these kinds of issues, please include logs. **Within 5 minutes of attempting to mount the volume**, run this command in the Terminal and include the full output in your bug report under the "Logs and crash reports" section:

```bash
sudo log show --last 5m --predicate "(subsystem in { 'com.apple.FSKit', 'com.apple.LiveFS' }) || (subsystem CONTAINS 'com.kpchew.ExtendFS') || (process in { 'diskarbitrationd', 'fskitd', 'fskit_agent' })"; diskutil list
```

If these logs are not included in the issue, the issue may be closed until they are provided.

## Crash reports

If the issue involves a crash (for example, the volume suddenly disappears), report the issue as a bug in the [issues tab](https://github.com/kthchew/ExtendFS/issues). Please check whether a crash report was generated in [Console.app > Crash Reports](https://support.apple.com/guide/console/reports-cnsl664be99a/mac). If so, attach it to your report.

It can also be useful to include logs collected by running the following command within 5 minutes of the crash:

```bash
sudo log collect --last 5m --predicate "subsystem CONTAINS 'com.kpchew.ExtendFS'"
```

While logs are not required if a crash report is provided, they can be very useful and I may request them if not provided.

## Other bugs

If the issue involves another kind of bug where you see an error occur, such as an input/output error, report the issue as a bug in the [issues tab](https://github.com/kthchew/ExtendFS/issues). Please include logs. You can get logs from the last 5 minutes with the below command (ideally, the volume both was mounted and the issue occurred in the last 5 minutes when you run this command, so run it as soon as possible after seeing the issue).

```bash
sudo log collect --last 5m --predicate "subsystem CONTAINS 'com.kpchew.ExtendFS'"
```

If these logs are not included in the issue and there is not enough information to diagnose the issue, the issue may be closed until they are provided.
