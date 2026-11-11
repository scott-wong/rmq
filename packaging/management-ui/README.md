# RMQ management console fork

This directory contains the static management UI used by the default Tongsuo
image. The Erlang backend and management API remain RabbitMQ 4.4.0.

The browser UI defaults to Simplified Chinese. Use the language selector on the
login page or header to switch to English. A URL parameter takes precedence
over the persisted choice:

```text
https://rmq.example.test:15671/?lang=zh-CN
https://rmq.example.test:15671/?lang=en-US
```

The selector stores the choice in `localStorage` under `rmq-language` and
reloads the page. The default is `zh-CN`; wrapped strings missing from the
catalog fall back to their English source text.

The image build precompiles `js/tmpl/*.ejs` with the upstream
`tools/precompile_ejs_templates` escript. The generated
`js/management-ejs.js` is not committed.

See `UPSTREAM.md` for provenance, the modification summary, update procedure and
license boundary.
