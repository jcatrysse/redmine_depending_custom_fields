(function () {
  window.showCustomFieldsWizard = function (issueIds) {
    var modal = document.createElement('div');
    modal.id = 'cf-wizard';
    modal.style.position = 'fixed';
    modal.style.top = 0;
    modal.style.left = 0;
    modal.style.right = 0;
    modal.style.bottom = 0;
    modal.style.background = 'rgba(0,0,0,0.3)';
    modal.style.display = 'flex';
    modal.style.alignItems = 'center';
    modal.style.justifyContent = 'center';

    var box = document.createElement('div');
    box.style.background = '#fff';
    box.style.padding = '20px';
    box.innerHTML = '<p>Loading...</p>';
    modal.appendChild(box);
    document.body.appendChild(modal);

    fetch('/dependable_custom_fields/options')
      .then(function (resp) { return resp.json(); })
      .then(function (data) {
        box.innerHTML = '';
        var select = document.createElement('select');
        data.forEach(function (opt) {
          var o = document.createElement('option');
          o.value = opt.id;
          o.textContent = opt.name;
          select.appendChild(o);
        });
        box.appendChild(select);
        var save = document.createElement('button');
        save.textContent = 'Save';
        save.style.marginLeft = '10px';
        save.onclick = function () {
          fetch('/dependable_custom_fields/save', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ issueIds: issueIds, value: select.value })
          }).then(function () { document.body.removeChild(modal); });
        };
        box.appendChild(save);
        var cancel = document.createElement('button');
        cancel.textContent = 'Cancel';
        cancel.onclick = function () { document.body.removeChild(modal); };
        box.appendChild(cancel);
      });
  };
})();
