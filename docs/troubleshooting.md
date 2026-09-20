# Troubleshooting

## DDEV acting up

Try a restart before digging further:

```bash
make restart      # ddev restart
```

If DDEV reports containers in a bad state, `ddev poweroff` (stops all
projects) followed by `make start` is the next step up.

## Composer running out of memory

Composer's own memory limit, not PHP's, is the usual culprit on large
dependency trees (LocalGov and Drupal CMS resolve a lot of packages). Disable
it for the one command that is failing:

```bash
ddev exec sh -c 'COMPOSER_MEMORY_LIMIT=-1 composer <command>'
```

## `make stan` reporting a spurious failure

Known caveat, not fixed at the Makefile level yet: `ddev exec vendor/bin/phpstan analyse ...`
can report exit 1 with zero real errors, a `ddev exec` / PHPStan process-exit
interaction rather than a real static-analysis failure. Running the same
command through a shell returns the correct exit code:

```bash
ddev exec bash -c "vendor/bin/phpstan analyse <path>"
```

If `make stan` fails with no errors printed, re-run it, or run the `bash -c`
form above, before assuming the code is broken.

## Staging a throwaway copy under `$TMPDIR` on Colima

If your Docker provider is [Colima](https://github.com/abiosoft/colima),
its default VM only mounts `$HOME`. A project staged under `$TMPDIR` (which
on macOS is typically under `/var/folders/...`) is invisible to the VM: DDEV
warns `/mnt/ddev_config is not mounted`, and `web/sites/default/files` ends
up owned by root and unwritable by the container user, so the site install
fails with "the directory ... is not writable". This is a host/Colima fact,
not a template bug. Stage throwaway copies under `$HOME` instead when using
Colima.
