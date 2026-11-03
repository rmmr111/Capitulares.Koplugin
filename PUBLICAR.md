# Publicar Capitulares v1.0 no GitHub — sem linha de comandos

1. Abre https://github.com/new e cria um **repositório público** chamado `capitulares.koplugin` (ou outro nome à tua escolha). Descrição sugerida: `Ornamental drop caps for KOReader • PT-PT / EN`. Não seleciones automaticamente uma licença; a decisão sobre a licença continua em aberto.
2. Extrai `Capitulares-v1.0-Repositorio.zip` para uma pasta no computador.
3. Entra no repositório e escolhe **Add file → Upload files**. Arrasta a pasta `capitulares.koplugin` e os ficheiros `.md` do pacote extraído. Confirma que a raiz do repositório contém diretamente `README.md` e `capitulares.koplugin/`.
4. Guarda os ficheiros no ramo principal.
5. Abre **Releases → Draft a new release**. Cria a tag `v1.0`, título `Capitulares v1.0` e cola o conteúdo de `RELEASE_NOTES_v1.0.md`.
6. Em **Assets**, anexa **`Capitulares-v1.0.zip`**. É o único instalador para Kobo e Kindle.
7. Publica a Release e confirma que o download do ZIP contém `capitulares.koplugin/main.lua`.

**Não carregues o ZIP do repositório como se fosse o instalador:** a Release deve anexar o ZIP universal, que contém apenas a pasta do plugin.

Pasta para instalação: Kobo `.adds/koreader/plugins/`; Kindle `koreader/plugins/`.
