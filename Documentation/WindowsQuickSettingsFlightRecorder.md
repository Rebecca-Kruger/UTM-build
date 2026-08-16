# Windows Quick Settings GPU flight recorder

This diagnostic build records the state immediately before DXMT submits Metal
work and enables Metal encoder execution status for each command buffer. It
does not change queue depth, asynchronous encoding, fences, command ordering,
presentation, or resource lifetime.

## Recorded layers

The DXMT main log (`tmp/*_dxmt.log`) records:

- device, queue, swapchain, and presenter lifetime;
- render, compute, mesh, and tile pipeline creation, including shader handles,
  attachment-format fingerprint, depth/stencil format, sample count, and
  topology;
- texture and texture-view creation, including handle, format, dimensions,
  mip levels, sample count, usage, and storage options;
- buffer creation and destruction, including GPU base address, allocation
  length, storage options, and suballocation information;
- shader argument values after DXMT writes the Metal argument table, including
  buffer GPU addresses, resource IDs, byte lengths, and UAV counter values;
- Metal command-buffer errors.

Each DXMT queue has three independent append-only files. The submit and detail
files have one writer (that queue's encode thread), and the completion file has
one writer (that queue's finish thread), so diagnostic logging does not
introduce a lock between queues:

```text
tmp/*_dxmt_queue_*.submit.flight.log
tmp/*_dxmt_queue_*.complete.flight.log
tmp/*_dxmt_queue_*.detail.flight.log
```

Every submit line includes a global submission id, DXMT queue id, sequence,
frame, Metal command-buffer handle, per-queue and global in-flight counts,
encoder mask, render/compute/blit/present counts, draw/dispatch/copy counts,
render-target dimensions and flags, and command/pipeline/resource/format
fingerprints. It also includes the final command, pipeline, and resource handle
so they can be joined directly to the creation records in the main DXMT log.
Completion is checkpointed every 16 command buffers and is always recorded on
an error. The detail stream contains one record for every encoder and command,
including encoder labels, debug-signpost ordinals, draw/dispatch/copy
parameters, attachment formats, buffer offsets, and resource handles. It is
intentionally high overhead and is only used by the isolated v2 package.

The Neptune log (`tmp/_npt_lifecycle.log`, with one rotated
`tmp/_npt_lifecycle.log.previous`) records:

- context, sync queue, and shared-resource lifetime;
- every 256 decoded calls: context id, byte/call totals, command groups, final
  command and object id, command-set fingerprint, and Win32 event totals;
- every 64 fence operations: submitted/retired/pending counts, high-water mark,
  timeout count, and final fence id;
- fatal decoder snapshots immediately when detected.

Every line uses a monotonic timestamp plus process and thread id. This allows
the Neptune stream, DXMT stream, UTM debug log, and the final iPadOS panic time
to be aligned without relying only on wall-clock time.

## Collection after a reboot

Do not launch the diagnostic UTM package again before collecting logs; its
files are append-only, but preserving the exact end of the failed session makes
analysis simpler. Find the data container for bundle id
`com.utmapp.UTMdxtrace2`, then copy all files matching:

```text
tmp/_npt_lifecycle.log*
tmp/*_dxmt.log
tmp/*_dxmt_queue_*.flight.log
tmp/*_dxmt_queue_*.detail.flight.log
Documents/*.log
Library/Logs/**
```

Also collect the newest entries under these system locations:

```text
/var/mobile/Library/Logs/CrashReporter/
/var/mobile/Library/Logs/CrashReporter/Panics/
/var/mobile/Library/Logs/CrashReporter/DiagnosticLogs/
```

Preserve file names and modification times. A recursive archive of only the
matching diagnostic package container plus the newest system panic/crash files
is preferred to copying the whole device.

## Decision matrix

- A final submit with no later completion, followed by an AGX panic, identifies
  the exact DXMT queue, pipeline, resource set, and encoder workload.
- Multiple queues with overlapping global in-flight counts and different final
  submissions isolates a cross-device/cross-queue concurrency path.
- Repeated failures with the same pipeline and format fingerprint isolate a
  pipeline or attachment compatibility path.
- A Neptune event/fence pending count that rises without retire progress points
  to the event/fence bridge rather than Metal encoding.
- A fatal Neptune snapshot before the last DXMT submit points to guest command
  decode or object lifetime.
- A completed DXMT checkpoint after the suspected workload, with no AGX panic,
  moves investigation above Metal (presentation/UI/process lifetime).

The recorder cannot guarantee attribution if iPadOS loses the final dirty file
pages during a kernel panic. It flushes every DXMT submit and every emitted
Neptune snapshot, while avoiding `fsync` because forcing storage on every frame
would materially change timing and power behavior.

