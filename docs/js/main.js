// PasteFlow Website Interactive Logic
document.addEventListener('DOMContentLoaded', () => {
  initSimDeck();
  initFaqAccordion();
  initCopyButtons();
});

// Interactive Simulator State
const sampleCards = [
  {
    id: 1,
    type: 'code',
    typeName: 'Swift',
    category: 'code',
    badge: '⌘ 1',
    content: `func pasteItem(_ item: ClipItem) {\n    let pboard = NSPasteboard.general\n    pboard.clearContents()\n    self.sendCmdV()\n}`,
    app: 'Xcode',
    time: '刚刚'
  },
  {
    id: 2,
    type: 'color',
    typeName: '色值',
    category: 'color',
    badge: '⌘ 2',
    colorHex: '#0A84FF',
    app: 'Figma',
    time: '2分钟前'
  },
  {
    id: 3,
    type: 'file',
    typeName: '文件',
    category: 'file',
    badge: '⌘ 3',
    fileName: 'PasteFlow.dmg',
    fileSize: '2.2 MB',
    app: 'Finder',
    time: '5分钟前'
  },
  {
    id: 4,
    type: 'link',
    typeName: '链接',
    category: 'link',
    badge: '⌘ 4',
    content: 'https://github.com/thesadboy/PasteFlow',
    app: 'Safari',
    time: '12分钟前'
  },
  {
    id: 5,
    type: 'text',
    typeName: '纯文本',
    category: 'text',
    badge: '⌘ 5',
    content: '重新想象 macOS 剪贴板的流转体验：更快、更轻、更纯粹。',
    app: 'Notes',
    time: '半小时前'
  },
  {
    id: 6,
    type: 'code',
    typeName: 'Shell',
    category: 'code',
    badge: '⌘ 6',
    content: `./scripts/run.sh # 编译并安装`,
    app: 'Terminal',
    time: '1小时前'
  }
];

let activeCategory = 'all';
let selectedIndex = 0;
let filteredItems = [...sampleCards];

function initSimDeck() {
  const deck = document.getElementById('simDeck');
  const tabs = document.querySelectorAll('.sim-tab');
  const searchInput = document.getElementById('simSearchInput');
  const toast = document.getElementById('copyToast');

  if (!deck) return;

  function renderDeck() {
    deck.innerHTML = '';
    
    if (filteredItems.length === 0) {
      deck.innerHTML = `<div style="padding: 40px; text-align: center; color: var(--text-tertiary); width: 100%;">未检索到符合条件的剪贴卡片</div>`;
      return;
    }

    filteredItems.forEach((item, index) => {
      const card = document.createElement('div');
      card.className = `clip-card ${index === selectedIndex ? 'selected' : ''}`;
      card.dataset.index = index;

      let bodyHtml = '';
      if (item.type === 'code') {
        bodyHtml = `<div class="clip-preview-code"><code>${escapeHtml(item.content)}</code></div>`;
      } else if (item.type === 'color') {
        bodyHtml = `
          <div class="clip-preview-color">
            <div class="color-swatch" style="background-color: ${item.colorHex};"></div>
            <div class="color-hex">${item.colorHex}</div>
          </div>
        `;
      } else if (item.type === 'file') {
        bodyHtml = `
          <div class="clip-preview-file">
            <div class="file-icon-wrap">
              <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path>
                <polyline points="14 2 14 8 20 8"></polyline>
              </svg>
            </div>
            <div class="file-name">${item.fileName}</div>
            <div class="file-meta">${item.fileSize}</div>
          </div>
        `;
      } else if (item.type === 'link') {
        bodyHtml = `<div class="clip-preview-text" style="color: #60a5fa; text-decoration: underline;">${escapeHtml(item.content)}</div>`;
      } else {
        bodyHtml = `<div class="clip-preview-text">${escapeHtml(item.content)}</div>`;
      }

      card.innerHTML = `
        <span class="clip-badge">${item.badge}</span>
        <div class="clip-header">
          <span>${item.typeName}</span>
          <span>•</span>
          <span>${item.app}</span>
        </div>
        <div class="clip-body">
          ${bodyHtml}
        </div>
        <div class="clip-footer">
          <span>${item.time}</span>
          <span>按 ↩ 模拟粘贴</span>
        </div>
      `;

      // Click to select, Double click to copy/paste
      card.addEventListener('click', () => {
        selectedIndex = index;
        updateSelection();
      });

      card.addEventListener('dblclick', () => {
        triggerSimPaste(item);
      });

      deck.appendChild(card);
    });

    scrollToSelected();
  }

  function updateSelection() {
    const cards = deck.querySelectorAll('.clip-card');
    cards.forEach((card, idx) => {
      if (idx === selectedIndex) {
        card.classList.add('selected');
      } else {
        card.classList.remove('selected');
      }
    });
    scrollToSelected();
  }

  function scrollToSelected() {
    const cards = deck.querySelectorAll('.clip-card');
    if (cards[selectedIndex]) {
      cards[selectedIndex].scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'center' });
    }
  }

  function triggerSimPaste(item) {
    if (!item) return;
    const contentToCopy = item.content || item.colorHex || item.fileName || '';
    if (navigator.clipboard) {
      navigator.clipboard.writeText(contentToCopy).catch(() => {});
    }
    
    // Show toast
    if (toast) {
      toast.classList.add('show');
      setTimeout(() => {
        toast.classList.remove('show');
      }, 2000);
    }
  }

  // Filter tabs
  tabs.forEach(tab => {
    tab.addEventListener('click', () => {
      tabs.forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
      activeCategory = tab.dataset.category;
      applyFilters();
    });
  });

  // Search filter
  if (searchInput) {
    searchInput.addEventListener('input', (e) => {
      applyFilters(e.target.value);
    });
  }

  function applyFilters(query = searchInput ? searchInput.value : '') {
    const q = (query || '').toLowerCase().trim();
    filteredItems = sampleCards.filter(item => {
      const matchCat = activeCategory === 'all' || item.category === activeCategory;
      const textMatch = (item.content || '').toLowerCase().includes(q) ||
                        (item.fileName || '').toLowerCase().includes(q) ||
                        (item.colorHex || '').toLowerCase().includes(q) ||
                        (item.typeName || '').toLowerCase().includes(q);
      return matchCat && (!q || textMatch);
    });
    selectedIndex = 0;
    renderDeck();
  }

  // Keyboard navigation on simulator
  window.addEventListener('keydown', (e) => {
    // If user is focused on an input element outside simulator, skip
    if (document.activeElement && document.activeElement.tagName === 'INPUT' && document.activeElement !== searchInput) {
      return;
    }

    if (e.key === 'ArrowRight') {
      if (selectedIndex < filteredItems.length - 1) {
        selectedIndex++;
        updateSelection();
        e.preventDefault();
      }
    } else if (e.key === 'ArrowLeft') {
      if (selectedIndex > 0) {
        selectedIndex--;
        updateSelection();
        e.preventDefault();
      }
    } else if (e.key === 'Enter') {
      if (filteredItems[selectedIndex]) {
        triggerSimPaste(filteredItems[selectedIndex]);
      }
    }
  });

  renderDeck();
}

// FAQ Accordion
function initFaqAccordion() {
  const faqItems = document.querySelectorAll('.faq-item');
  faqItems.forEach(item => {
    const question = item.querySelector('.faq-question');
    if (!question) return;

    question.addEventListener('click', () => {
      const isActive = item.classList.contains('active');
      faqItems.forEach(i => i.classList.remove('active'));
      if (!isActive) {
        item.classList.add('active');
      }
    });
  });
}

// Copy Code Buttons
function initCopyButtons() {
  const copyButtons = document.querySelectorAll('.btn-copy-code');
  copyButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      const code = btn.dataset.code || btn.previousElementSibling?.textContent;
      if (code) {
        navigator.clipboard.writeText(code.trim()).then(() => {
          const originalText = btn.textContent;
          btn.textContent = '已复制!';
          btn.style.color = 'var(--accent-emerald)';
          setTimeout(() => {
            btn.textContent = originalText;
            btn.style.color = '';
          }, 2000);
        });
      }
    });
  });
}

function escapeHtml(str) {
  if (!str) return '';
  return str.replace(/[&<>"']/g, function(m) {
    return {
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#039;'
    }[m];
  });
}
