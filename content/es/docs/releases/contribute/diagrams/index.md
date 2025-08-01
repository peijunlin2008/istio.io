---
title: Diagram Creation Guidelines
description: Provides assets and instructions to create diagrams for the Istio documentation.
weight: 13
aliases:
   - /about/contribute/diagrams
   - /latest/about/contribute/diagrams
keywords: [contribute,diagram,documentation,guide]
owner: istio/wg-docs-maintainers
test: n/a
---

Welcome to the Istio diagram guide!

The guide is available as an [SVG file](./diagram-guidelines.svg) or as a
[Google Drawings file](https://docs.google.com/drawings/d/1f3NyutAQIDOA8ojGNyMA5JAJllDShZGQAFfdD01XdSc/edit)
to allow you to reuse the shapes and styles with ease. Use these guidelines to
create SVG diagrams for the Istio website using any vector graphics tool like
Google Drawings, Inkscape, or Illustrator. Please ensure that the text in your
diagrams remains editable.

Our goal is to drive consistency across all diagrams in our website to ensure
diagrams are clear, technically accurate, and accessible.

Keeping the text editable allows the community to improve and change the
diagrams as needed.

To create your diagrams, follow these steps:

1. Refer to the [guide](./diagram-guidelines.svg) and copy-paste from it as
   needed.
1. Connect the shapes with the appropriate style of line.
1. Label the shapes and lines with descriptive yet short text.
1. Add a legend for any labels that apply multiple times.
1. [Contribute](/es/docs/releases/contribute/add-content) your diagram to our
   documentation.

If you create the diagram in Google Drawings, follow these steps:

1. Put your diagram in our [shared drive](https://drive.google.com/corp/drive/u/0/folders/17r1m4nfyr9xbfbpMqZsreMvFLCD4bgvx).
1. When the diagram is complete, export it as SVG and include the SVG
   file in your PR.
1. Leave a comment in the Markdown file containing the diagram with the
   URL to the Google Drawings file.

If your diagram depicts a process, **do not add the descriptions of the steps**
to the diagram. Instead, only add the numbers of the steps to the diagram and
add the descriptions of the steps as a numbered list in the document. Ensure
that the numbers on the list match the numbers on your diagram. This approach
helps make diagrams easier to understand and the content more accessible.

Thank you for contributing to the Istio documentation!

{{< image width="75%"
    link="./diagram-guidelines.svg"
    alt="The Istio diagram creation guidelines in SVG format."
    title="The Istio Diagram Creation Guidelines"
    >}}
