# Logos de provedor (SPEC-094 R14)

Os arquivos desta pasta são cópias **sem alteração** dos originais. O app não os carrega em tempo de execução: o `path` de cada um foi copiado para `lib/ui/providers/provider_logo_paths.dart` e é pintado por um `CustomPainter` (sem `flutter_svg`).

| Arquivo | Origem | Licença do arquivo | Marca | sha256 |
|---|---|---|---|---|
| `claude.svg` | [Simple Icons 16.38.0](https://cdn.jsdelivr.net/npm/simple-icons@16.38.0/icons/claude.svg), slug `claude` | CC0 1.0 (Simple Icons) | Claude é marca da Anthropic | `2d6fda79eb18ddccca35b799eeb3cece0dfabc22520ce3b10abd25668df9fa93` |
| `openai-blossom.svg` | `OpenAI-logos/SVGs/OAI_OpenAI-Blossom_White.svg` do pacote oficial [cdn.openai.com/brand/openai-logos.zip](https://cdn.openai.com/brand/openai-logos.zip), linkado em [openai.com/brand](https://openai.com/brand) | Uso sob os termos de openai.com/brand | OpenAI e o logo Blossom são marcas da OpenAI | `01d158767c4eec0e47bd617e67759c33da0accd1438be1a8d29dfdb99ce87285` |

Os logos servem só para identificar qual provedor executa uma tarefa. Não indicam parceria, patrocínio nem endosso, e nunca são usados como ícone ou marca do Promptorium. A forma e a cor ficam intactas: o Claude sempre em `#D97757` e o Blossom no branco oficial. O único ajuste é o enquadramento do Blossom (viewBox `176 176 364 364`), que corta só a margem vazia do arquivo.

Se os termos da OpenAI não permitirem o uso, troque `codexUsesOfficialLogo` para `false` em `lib/ui/providers/provider_logos.dart`: o Codex passa a usar o glifo do livro no app inteiro.
