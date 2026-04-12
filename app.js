const STORAGE_KEY = 'budget-tracker-transactions';

let transactions = [];

function loadTransactions() {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    transactions = stored ? JSON.parse(stored) : [];
  } catch {
    transactions = [];
  }
}

function saveTransactions() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(transactions));
}

function addTransaction(description, amount, type) {
  transactions.push({ id: Date.now().toString(), description, amount, type });
  saveTransactions();
  render();
}

function deleteTransaction(id) {
  transactions = transactions.filter((t) => t.id !== id);
  saveTransactions();
  render();
}

function formatCurrency(value) {
  return '$' + value.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

const arrowUpSVG = `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 19V5M5 12l7-7 7 7"/></svg>`;
const arrowDownSVG = `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5v14M19 12l-7 7-7-7"/></svg>`;
const trashSVG = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14H6L5 6"/><path d="M10 11v6M14 11v6"/><path d="M9 6V4h6v2"/></svg>`;

function render() {
  const totalIncome = transactions
    .filter((t) => t.type === 'income')
    .reduce((sum, t) => sum + t.amount, 0);

  const totalExpenses = transactions
    .filter((t) => t.type === 'expense')
    .reduce((sum, t) => sum + t.amount, 0);

  const balance = totalIncome - totalExpenses;

  const balanceEl = document.getElementById('balance');
  balanceEl.textContent = formatCurrency(balance);
  balanceEl.classList.toggle('negative', balance < 0);

  document.getElementById('total-income').textContent = formatCurrency(totalIncome);
  document.getElementById('total-expenses').textContent = formatCurrency(totalExpenses);

  const list = document.getElementById('transaction-list');
  list.innerHTML = '';

  if (transactions.length === 0) {
    list.innerHTML = `
      <li class="empty-state">
        <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" opacity="0.3"><rect x="2" y="5" width="20" height="14" rx="2"/><path d="M2 10h20"/></svg>
        <p>No transactions yet</p>
        <span>Add your first one above</span>
      </li>`;
    return;
  }

  [...transactions].reverse().forEach((t) => {
    const li = document.createElement('li');
    li.className = `transaction-item ${t.type}`;

    li.innerHTML = `
      <span class="tx-badge">${t.type === 'income' ? arrowUpSVG : arrowDownSVG}</span>
      <div class="tx-info">
        <p class="tx-desc">${escapeHtml(t.description)}</p>
        <p class="tx-type-label">${t.type}</p>
      </div>
      <span class="tx-amount">${t.type === 'expense' ? '−' : '+'}${formatCurrency(t.amount)}</span>
      <button class="btn-delete" aria-label="Delete ${escapeHtml(t.description)}">${trashSVG}</button>
    `;

    li.querySelector('.btn-delete').addEventListener('click', () => deleteTransaction(t.id));
    list.appendChild(li);
  });
}

function escapeHtml(str) {
  return str.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function showError(msg) {
  document.getElementById('error-msg').textContent = msg;
}

function clearError() {
  document.getElementById('error-msg').textContent = '';
}

// ── Type Toggle ──
document.getElementById('type-toggle').addEventListener('click', (e) => {
  const btn = e.target.closest('.toggle-btn');
  if (!btn) return;
  document.querySelectorAll('.toggle-btn').forEach((b) => b.classList.remove('active'));
  btn.classList.add('active');
  document.getElementById('tx-type').value = btn.dataset.value;
});

// ── Form Submit ──
document.getElementById('transaction-form').addEventListener('submit', (e) => {
  e.preventDefault();

  const description = document.getElementById('description').value.trim();
  const amountRaw = document.getElementById('amount').value.trim();
  const type = document.getElementById('tx-type').value;

  if (!description) { showError('Please enter a description.'); return; }

  const amount = parseFloat(amountRaw);
  if (!amountRaw || isNaN(amount) || amount <= 0) {
    showError('Please enter a valid amount greater than 0.');
    return;
  }

  clearError();
  addTransaction(description, Math.round(amount * 100) / 100, type);

  document.getElementById('description').value = '';
  document.getElementById('amount').value = '';
  document.getElementById('description').focus();
});

loadTransactions();
render();
