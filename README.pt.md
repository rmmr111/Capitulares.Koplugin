# Capitulares — KOReader plugin

**v1.0** · Português (Portugal) / English · Plugin independente e não oficial do KOReader.

O **Capitulares** acrescenta letras capitulares ornamentais aos EPUBs abertos no KOReader. Permite escolher fontes decorativas e afinar o aspeto por livro, sem modificar o EPUB original.

## Funcionalidades

- Capitulares automáticas no início dos capítulos e subcapítulos elegíveis.
- Capitulares adicionais **por livro**, com intervalos por parágrafos ou por **ecrãs refluíveis**, reiniciando a contagem em cada capítulo.
- Seleção de fontes ornamentais, fontes do leitor ou fonte do próprio livro, com pré-visualização.
- Tamanho, espaçamento horizontal e vertical, perfis por fonte, capitular padrão e reposição.
- Ativação por livro; painel Editorial Premium; acesso em **Ferramentas → Capitulares** durante a leitura de EPUBs.
- Suporte a EPUBs com parágrafos dentro de `div` aninhados e texto dentro de `span`.
- No modo por ecrãs, evita transformar travessões de diálogo (`—`, `–`, `-`) em capitulares: procura um parágrafo narrativo elegível.
- Cor opcional da capitular em dispositivos com ecrã a cores reconhecidos pelo KOReader; opção **Original** e nove cores, guardadas por livro.
- Preservação do texto original, incluindo iniciais acentuadas: a normalização do desenho só é usada quando necessária.

**Nota:** como os EPUBs são refluíveis, a introdução de letras capitulares pode alterar a paginação. Nem todos os ecrãs possuem um parágrafo novo elegível. A distribuição por ecrãs não é matematicamente exata em todos os livros.

## Instalar — um único ZIP universal

Descarrega **`Capitulares-v1.0.zip`** em **Releases**. O arquivo contém apenas a pasta `capitulares.koplugin/` na raiz. Não precisas de PowerShell, aplicações adicionais ou dois instaladores diferentes.

1. Fecha completamente o KOReader e liga o leitor ao computador.
2. Extrai o **conteúdo do ZIP** para a pasta dos plugins correspondente ao teu dispositivo:

   | Dispositivo | Pasta dos plugins |
   | --- | --- |
   | Kobo | `.adds/koreader/plugins/` |
   | Kindle | `koreader/plugins/` |

3. Confirma que o caminho termina em `plugins/capitulares.koplugin/main.lua` (sem pastas duplicadas).
4. Ejeta o dispositivo, reinicia o KOReader e abre um **EPUB sem DRM dentro do KOReader**.
5. Abre **Ferramentas → Capitulares → Ativar neste livro**, e depois **Personalizar capitular**.

O plugin não funciona no leitor nativo do Kindle nem é apresentado no explorador de ficheiros do KOReader. As opções dependem das capacidades de renderização do aparelho.

## Utilização

Em **Personalizar capitular**, seleciona o tipo de letra e ajusta o seu tamanho e espaçamento. Em **Avançado**, podes ativar capitulares adicionais, escolher **Parágrafos** ou **Ecrãs** e definir o intervalo. A contagem por ecrãs recomeça na capitular inicial de cada capítulo. Os parágrafos de diálogo não são usados como destino adicional no modo por ecrãs.

Se o KOReader identificar um ecrã a cores e a renderização a cores estiver ativa, podes escolher **Cor da capitular** em **Avançado**. O valor **Original** preserva a cor do EPUB. Em ecrãs monocromáticos, a cor personalizada não é aplicada.

Uma mudança de estilos pode pedir um recálculo inicial do KOReader; **avisos repetidos durante a leitura não são o comportamento esperado**.

## Fontes ornamentais

As fontes não fazem parte da distribuição. Consulta **[FONTS.md](FONTS.md)** (ou [FONTS.en.md](FONTS.en.md)) para os links recomendados e as notas de licença. As fontes TTF/OTF podem ser colocadas, por exemplo, em `.adds/koreader/fonts/Initials/` no Kobo.

## Compatibilidade

- **Kobo Libra 2:** fluxo principal testado com KOReader v2026.07.2.
- **Kindle Colorsoft:** a deteção de estruturas EPUB e os diálogos foram desenvolvidos a partir de testes no dispositivo; não está garantido comportamento idêntico com todos os EPUBs e configurações. A apresentação das cores ainda carece de validação visual completa.
- **EPUB:** é o formato visado; o KOReader usa diferentes motores para diferentes formatos, pelo que não se promete suporte universal a AZW3, MOBI, KFX ou documentos com DRM.

## Código e direitos

O código é disponibilizado publicamente, mas **ainda não foi escolhida uma licença de código aberto**. Na ausência de licença explícita, aplicam-se os direitos de autor por defeito; não interpretes a disponibilidade pública como autorização geral para redistribuir ou modificar o código. As licenças das fontes externas são independentes e devem ser respeitadas.

Projeto da comunidade; não afiliado à equipa oficial do KOReader.

**English:** [README.en.md](README.en.md) · **Notas:** [CHANGELOG.md](CHANGELOG.md)
