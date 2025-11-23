# Bug Reports, Requests, and Questions

If you just have a general question, you can ask in the [discussions tab](https://github.com/kthchew/ExtendFS/discussions).

You can submit bug reports or requests in the [issues tab](https://github.com/kthchew/ExtendFS/issues). Before you do so, please update to the latest macOS (at the very least, the latest version for the major macOS release you are on) that you can, as some bugs might be FSKit bugs.

If the issue involves a crash (for example, the volume suddenly disappears), please check whether a crash report was generated in [Console.app > Crash Reports](https://support.apple.com/guide/console/reports-cnsl664be99a/mac). If so, please attach it to your report.

If the issue involves another kind of bug where you see an error occur, such as an input/output error, please include logs. You can get logs from the last 5 minutes with the below command (ideally, the volume both was mounted and the issue occurred in the last 5 minutes when you run this command, so run it as soon as possible after seeing the issue).

```bash
sudo log collect --last 5m --predicate "subsystem=='com.kpchew.ExtendFS.ext4Extension'"
```

Sometimes these logarchive files can be very large. You might need to upload them somewhere else and include a link in your report. You might also be able to paste the log contents into a text file and then upload the text file instead.

Note that issues you open are public, which includes any attachments you send. Please don't send private data unless requested and it is absolutely necessary to troubleshoot an issue. By default, information like directory names and contents are not visible in the logs.
