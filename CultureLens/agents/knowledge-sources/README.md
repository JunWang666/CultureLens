# Knowledge pack sources

Editable per-topic knowledge packs. The App ships a single merged pack under
`CultureLens/Resources/KnowledgePack/` (ODR tag `knowledge-base`).

Merge order (earlier wins on id collision):

1. `west-lake`
2. `chinese-history`
3. `liangzhu`
4. `zhejiang-museum`

Regenerate the shipped pack:

```bash
python3 scripts/merge_knowledge_packs.py
```
