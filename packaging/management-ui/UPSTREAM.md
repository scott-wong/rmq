# Management console upstream

This directory is a source-level fork of the RabbitMQ 4.4.0 management
console. It is not a RabbitMQ upstream project and is not supported by the
RabbitMQ team.

| Field | Value |
|---|---|
| Upstream project | `rabbitmq/rabbitmq-server` |
| Upstream tag | `v4.4.0` |
| Upstream commit | `24d5157cd415ef396c8ecd40a2d08c4d7ad3da9f` |
| Source path | `deps/rabbitmq_management/priv/www` |
| Pristine tree SHA256 | `04d8d3746605e19a5a1dd38af90ed465ae38c7f6f61277515d3aa0ad9313232e` |
| RMQ fork | `rabbitmq-management-4.4.0` |
| Default language | `zh-CN` |
| Other language | `en-US` |

The tree digest is calculated over sorted relative file paths and each file's
SHA256 content digest. It identifies the pristine upstream input from which
this fork started; it does not describe the modified tree.

## RMQ changes

- Added source-level `t()` calls and a Chinese catalog.
- Added the `zh-CN` / `en-US` language selector and URL/local-storage
  persistence.
- Rebranded the login page, header, page title, favicon and version badge.
- Added RMQ light and dark compact logos and CJK-friendly typography.
- Added a generated `rmq-build-info.js` in the image build.
- Removed the RabbitMQ logo from the management UI shell.

The RabbitMQ management API, Erlang routes, authentication and data model are
not forked. Only static `priv/www` assets are replaced at image build time.

## Updating

Check out the desired upstream RabbitMQ tag, then compare:

```sh
scripts/diff-management-ui-upstream.sh /path/to/rabbitmq-server
```

Review upstream changes, port translations and branding deliberately, update
this lock file, and run the full image and browser acceptance tests. Do not
blindly replace this directory with a new upstream `priv/www`.

Licenses and notices are preserved under `licenses/`. The fork remains subject
to RabbitMQ's MPL-2.0 terms, and bundled MIT/BSD/ISC components retain their
original notices.
