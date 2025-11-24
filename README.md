# ExtendFS

ExtendFS is a read-only ext2, ext3, and ext4 driver for macOS using FSKit and written in Swift. It's plug-and-play, with no kernel extension or messing with system security settings required.

macOS 15.6 or later is required.

## Download

You can either download the latest version from the [releases page](https://github.com/kthchew/ExtendFS/releases) on GitHub for free, or purchase it from the [Mac App Store](https://apps.apple.com/us/app/extendfs-for-linux-filesystems/id6755664332). There is no difference in functionality.

<a href="https://apps.apple.com/us/app/extendfs-for-linux-filesystems/id6755664332?mt=12&itscg=30200&itsct=apps_box_badge&mttnsubad=6755664332" style="display: inline-block;">
<img src="https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/black/en-us?releaseDate=1763942400" alt="Download on the App Store" style="width: 245px; height: 82px; vertical-align: middle; object-fit: contain;" />
</a>

## Usage

1. Download and run the ExtendFS app.
2. Enable ExtendFS's file system extension in System Settings.

Then, once you plug in your ext4-formatted drive or open your disk image, supported volumes will mount automatically, with no command line tools or manual mounting required.

If you do wish to use a command line tool, ExtendFS (like other FSKit extensions) integrates with the system's familiar tools, like the `mount(8)` command:

```bash
mount -t ExtendFS /dev/disk15 /tmp/mnt
```

## Known Limitations

- Not all ext4 features are supported. The following feature flags _are_ supported: `filetype`, `extents`, `64bit`, `flex_bg`, `csum_seed` [1]. If your volume requires other features, like `inline_data` or `meta_bg`, it won't mount.
- LVM is not currently supported.
- Performance may be lower than it would be with a kernel extension (e.g. FB21069313). A large part of this is FSKit overhead, but there is also likely some room for improvement in this code.
- As stated above, this is a read-only implementation. You cannot write data to an ext4 volume using ExtendFS.
    - Write-related options such as creating new folders or deleting items might unexpectedly appear in the Finder. This is an FSKit bug (actually, various bugs - FB19241327, FB21068845). Performing those actions does not actually write any data to the disk.
- If there are multiple hard links to the same file in a folder, only one of the hard links appears in the Finder (FB21021220). You can still use command line tools like `ls(1)` to enumerate the hard links.

FSKit is still very young and Apple is rapidly adding new features and fixing bugs in the framework in macOS updates. I encourage you to use the latest version of macOS possible if you are encountering issues.

[1] ExtendFS does not currently verify checksums at all.

## FAQ

### What's the difference between the version available on GitHub and the Mac App Store version?

There's no code differences. They're the same build with exactly the same functionality. The only difference is that the App Store can handle automatic updates for you if you want (which, depending on your perspective, might be a benefit or a drawback). If you want to support this project, you can purchase the App Store version, but otherwise the app is free.

### Why is macOS 15.6 required?

FSKit first released in macOS 15.4, so ExtendFS can't support any version of macOS below that. macOS 15.4 and 15.5 had significant issues in FSKit that made it much more complicated to mount disks (FB17772372), and since any device that can support macOS 15.4 can also support macOS 15.6, I set the minimum version to 15.6 to make things more simple.

### I have a bug or question, where can I go to ask about that?

Please see [here](SUPPORT.md) for information about that.

### Will read-write support ever come to ExtendFS?

Maybe...

Probably not.

### Will support for other Linux filesystems (like Btrfs) ever come to ExtendFS?

I'd say read-only support for other filesystems is slightly more of a possibility than read-write support in general, although the answer is still "probably not."

In the immediate future, though, I can say this is almost definitely a "no," at least for the specific case of Btrfs. My understanding is that Btrfs has subvolumes as a key feature, as in one block device might present multiple volumes to the system. However, the current version of FSKit only supports what Apple calls "unary file systems," which essentially means one block device (resource) presents one volume. Apple has indicated that future versions of FSKit will support more complex file systems, but it is not there yet.

### What are the FB numbers that have been appearing in this document?

Those are Apple feedback numbers for various bugs I filed against FSKit. You unfortunately can't see them, but they're mostly for my own reference (or to reference by an Apple employee, if they happen to come across this).

### Other tools like `ext4fuse` exist, why did you make this?

A few reasons:
- Most other tools don't integrate very well with the system's frameworks, like Disk Arbitration (for disk automounting).
- Implementations like macFUSE are fairly difficult to install on Apple Silicon machines because installing kernel extensions requires reducing your system security level in recovery mode. (This is less of a problem as newer versions of macFUSE do support FSKit and alternatives like FUSE-T exist, although the kernel extension is still used by default.)
- I found it fun and it was a cool learning opportunity. FSKit is new and fairly uncharted territory so it's pretty interesting to try to make something useful with it.

### You have a sick sense of fun.

That's not a question.

## Contributing

See the [contributing guidelines](CONTRIBUTING.md).

## License

[GPLv3 or later with app store exception](LICENSE.md)
