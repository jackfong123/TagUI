// Generalized MyKeeta product-description optimizer
// Usage examples -
// ./tagui flows/samples/mykeeta_optimize_descriptions.tag -chrome single '港泰蝦餃皇'
// ./tagui flows/samples/mykeeta_optimize_descriptions.tag -chrome top_n 5
// p1 = mode (single | top_n), p2 = product name or count

js begin
mode = (p1 || 'single').toLowerCase().replace(/-/g, '_').trim()
raw_target = (p2 || '').trim()
if (mode !== 'top_n' && mode !== 'single') mode = 'single'
batch_limit = parseInt(raw_target, 10)
if (!batch_limit || batch_limit < 1) batch_limit = 1
target_name = raw_target
target_count = 0
batch_targets = []
current_name = ''
current_zh_desc = ''
current_en_desc = ''

normalize_product_name = function(name) {
    return (name || '')
        .replace(/^\s+|\s+$/g, '')
        .replace(/^[0-9]+[\s._-]*/, '')
        .replace(/周期性可售招牌/g, '')
        .replace(/周期性可售/g, '')
        .replace(/可售招牌/g, '')
        .replace(/招牌/g, '')
        .replace(/\s+/g, ' ')
        .replace(/^\s+|\s+$/g, '')
}

generate_descriptions = function(name) {
    var product_name = normalize_product_name(name)
    var lower_name = product_name.toLowerCase()
    var has_shrimp = /蝦|虾|shrimp|prawn/.test(product_name) || /shrimp|prawn/.test(lower_name)
    var has_siumai = /燒賣|烧卖|燒麦|烧麦|siumai|siu mai|shumai/.test(product_name) || /siumai|siu mai|shumai/.test(lower_name)
    var has_dumpling = /餃|饺|dumpling|har gow|gow/.test(product_name) || /dumpling|har gow/.test(lower_name)
    var has_spicy = /辣|香辣|spicy|chili|chilli/.test(product_name) || /spicy|chili|chilli/.test(lower_name)

    var zh_intro = product_name + '严选食材现点现做'
    var zh_texture = '口感层次更丰富'
    var zh_finish = '香气与鲜味更集中，趁热享用更出色。'

    var en_intro = product_name + ' is freshly prepared with carefully selected ingredients'
    var en_texture = 'for a fuller texture and cleaner finish'
    var en_finish = 'Best enjoyed hot for the most satisfying bite.'

    if (has_shrimp) {
        zh_intro = product_name + '严选鲜虾入馅，鲜甜弹嫩更饱满'
        en_intro = product_name + ' is packed with juicy shrimp and prepared fresh to keep every bite naturally sweet and springy'
    }
    if (has_siumai) {
        zh_texture = '蒸后肉汁更丰盈，港式风味更地道'
        en_texture = 'with rich juices released through steaming and a classic Hong Kong-style profile'
    }
    else if (has_dumpling) {
        zh_texture = '皮薄馅满，入口更显鲜香爽弹'
        en_texture = 'with a delicate wrapper, generous filling, and a bouncy bite'
    }
    if (has_spicy) {
        zh_finish = '辣香更有层次，尾韵更开胃，趁热享用更过瘾。'
        en_finish = 'The layered heat lifts the aroma and makes it even more appetizing when served hot.'
    }

    return {
        zh: zh_intro + '，' + zh_texture + '，' + zh_finish,
        en: en_intro + ', ' + en_texture + '. ' + en_finish
    }
}
js finish

https://merchant.mykeeta.com/web/product
wait 12

if mode equals to 'top_n'
    dom_json = {limit: batch_limit}
    dom begin
    try {
      function clean(value) {
        return (value || '').replace(/\s+/g, ' ').replace(/^\s+|\s+$/g, '')
      }
      var payload = {iframeFound: false, targets: [], url: location.href}
      var frame = document.querySelector('#merchant_mainContentIframe, iframe')
      if (!frame) return JSON.stringify(payload)
      payload.iframeFound = true
      var doc = frame.contentDocument || (frame.contentWindow && frame.contentWindow.document)
      if (!doc) return JSON.stringify(payload)

      var rows = doc.querySelectorAll('tr')
      var limit = Number(dom_json.limit || 1)
      var i = 0
      for (i = 0; i < rows.length; i++) {
        var text = clean(rows[i].textContent || rows[i].innerText)
        if (!text) continue
        var editLink = rows[i].querySelector('span.spu-table-action-link')
        if (!editLink || clean(editLink.textContent || editLink.innerText) !== '编辑') continue
        var nameCell = rows[i].querySelector('td')
        var productName = clean((nameCell && (nameCell.textContent || nameCell.innerText)) || text)
        productName = productName.replace(/^\d+/, '')
        productName = clean(productName)
        productName = productName
          .replace(/周期性可售招牌/g, '')
          .replace(/周期性可售/g, '')
          .replace(/可售招牌/g, '')
          .replace(/招牌/g, '')
        productName = clean(productName)
        if (!productName) continue
        payload.targets.push(productName)
        if (payload.targets.length >= limit) break
      }
      return JSON.stringify(payload)
    }
    catch (e) {
      return JSON.stringify({error: e && e.message ? e.message : 'unknown-error', url: location.href})
    }
    dom finish
    echo batch_target_probe=`dom_result`

    js begin
    batch_payload = {}
    try {batch_payload = JSON.parse(dom_result || '{}')} catch (e) {batch_payload = {}}
    batch_targets = (batch_payload.targets && batch_payload.targets.length) ? batch_payload.targets : []
    target_count = batch_targets.length
    js finish
else
    target_count = 1
    js begin
    batch_targets = [normalize_product_name(target_name)]
    target_name = batch_targets[0]
    js finish

echo mykeeta_mode=`mode`
echo mykeeta_target_count=`target_count`

for item_index from 1 to target_count
    if item_index greater than 1
        https://merchant.mykeeta.com/web/product
        wait 10

    js begin
    current_name = batch_targets[item_index - 1] || ''
    current_desc = generate_descriptions(current_name)
    current_zh_desc = current_desc.zh
    current_en_desc = current_desc.en
    js finish

    echo optimizing_product=`current_name`

    dom_json = {productName: current_name}
    dom begin
    try {
      function clean(value) {
        return (value || '').replace(/\s+/g, ' ').replace(/^\s+|\s+$/g, '')
      }
      function isVisible(el) {
        if (!el) return false
        if (el.offsetParent !== null) return true
        if (el.getClientRects && el.getClientRects().length > 0) return true
        return false
      }
      function setInputValue(win, el, value) {
        if (!el) return false
        var proto = el.tagName === 'TEXTAREA' ? win.HTMLTextAreaElement.prototype : win.HTMLInputElement.prototype
        var descriptor = Object.getOwnPropertyDescriptor(proto, 'value')
        if (descriptor && descriptor.set) descriptor.set.call(el, value)
        else el.value = value
        el.focus()
        el.dispatchEvent(new win.Event('input', {bubbles: true}))
        el.dispatchEvent(new win.Event('change', {bubbles: true}))
        el.dispatchEvent(new win.KeyboardEvent('keydown', {bubbles: true, key: 'Enter', code: 'Enter', keyCode: 13, which: 13}))
        el.dispatchEvent(new win.KeyboardEvent('keyup', {bubbles: true, key: 'Enter', code: 'Enter', keyCode: 13, which: 13}))
        if (typeof el.blur === 'function') el.blur()
        return true
      }

      var payload = {iframeFound: false, searchFound: false, rowFound: false, clickedEdit: false, searchedName: clean(dom_json.productName), url: location.href}
      var frame = document.querySelector('#merchant_mainContentIframe, iframe')
      if (!frame) return JSON.stringify(payload)
      payload.iframeFound = true
      var win = frame.contentWindow
      var doc = frame.contentDocument || (win && win.document)
      if (!doc || !win) return JSON.stringify(payload)

      var searchInput = doc.querySelector('input[placeholder="搜索商品名称"]')
      if (searchInput) {
        payload.searchFound = true
        setInputValue(win, searchInput, clean(dom_json.productName))
      }

      var rows = doc.querySelectorAll('tr')
      var i = 0
      for (i = 0; i < rows.length; i++) {
        var text = clean(rows[i].textContent || rows[i].innerText)
        if (!text || text.indexOf(clean(dom_json.productName)) === -1) continue
        payload.rowFound = true
        var editLink = rows[i].querySelector('span.spu-table-action-link')
        if (editLink && clean(editLink.textContent || editLink.innerText) === '编辑' && isVisible(editLink)) {
          editLink.click()
          payload.clickedEdit = true
        }
        break
      }
      return JSON.stringify(payload)
    }
    catch (e) {
      return JSON.stringify({error: e && e.message ? e.message : 'unknown-error', url: location.href})
    }
    dom finish
    echo open_editor_result=`dom_result`

    wait 10

    dom_json = {productName: current_name, zhDesc: current_zh_desc, enDesc: current_en_desc}
    dom begin
    try {
      function clean(value) {
        return (value || '').replace(/\s+/g, ' ').replace(/^\s+|\s+$/g, '')
      }
      function isVisible(el) {
        if (!el) return false
        if (el.offsetParent !== null) return true
        if (el.getClientRects && el.getClientRects().length > 0) return true
        return false
      }
      function nearFieldLabel(el) {
        var node = el
        var hop = 0
        while (node && hop < 6) {
          var text = clean(node.textContent || node.innerText)
          if (text && text.length <= 120) return text
          node = node.parentElement
          hop += 1
        }
        return ''
      }
      function setAreaValue(win, el, value) {
        if (!el) return false
        var descriptor = Object.getOwnPropertyDescriptor(win.HTMLTextAreaElement.prototype, 'value')
        if (descriptor && descriptor.set) descriptor.set.call(el, value)
        else el.value = value
        el.focus()
        el.dispatchEvent(new win.Event('input', {bubbles: true}))
        el.dispatchEvent(new win.Event('change', {bubbles: true}))
        if (typeof el.blur === 'function') el.blur()
        el.dispatchEvent(new win.Event('blur', {bubbles: true}))
        return true
      }

      var payload = {
        iframeFound: false,
        zhFound: false,
        enFound: false,
        saved: false,
        textareas: [],
        url: location.href
      }
      var frame = document.querySelector('#merchant_mainContentIframe, iframe')
      if (!frame) return JSON.stringify(payload)
      payload.iframeFound = true
      var win = frame.contentWindow
      var doc = frame.contentDocument || (win && win.document)
      if (!doc || !win) return JSON.stringify(payload)

      var textareas = doc.querySelectorAll('textarea')
      var visibleAreas = []
      var i = 0
      for (i = 0; i < textareas.length; i++) {
        if (!isVisible(textareas[i])) continue
        var areaInfo = {
          placeholder: clean(textareas[i].getAttribute('placeholder') || ''),
          value: clean(textareas[i].value || ''),
          label: nearFieldLabel(textareas[i]).slice(0, 120)
        }
        payload.textareas.push(areaInfo)
        visibleAreas.push(textareas[i])
      }

      var zhField = doc.querySelector('textarea[placeholder="请描述您的商品"]')
      if (!zhField || !isVisible(zhField)) zhField = null

      var englishCandidates = []
      for (i = 0; i < visibleAreas.length; i++) {
        var area = visibleAreas[i]
        if (zhField && area === zhField) continue
        var placeholder = clean(area.getAttribute('placeholder') || '')
        var label = nearFieldLabel(area)
        var value = clean(area.value || '')
        if (placeholder.indexOf('商品名称') !== -1 || label.indexOf('商品名称') !== -1) continue
        englishCandidates.push({el: area, placeholder: placeholder, label: label, value: value})
      }

      var enField = null
      for (i = 0; i < englishCandidates.length; i++) {
        var candidate = englishCandidates[i]
        var text = (candidate.placeholder + ' ' + candidate.label).toLowerCase()
        if (text.indexOf('english') !== -1 || text.indexOf('英文') !== -1) {
          enField = candidate.el
          break
        }
      }
      if (!enField) {
        for (i = 0; i < englishCandidates.length; i++) {
          var fallback = englishCandidates[i]
          var combined = (fallback.placeholder + ' ' + fallback.label + ' ' + fallback.value).toLowerCase()
          if (combined.indexOf('description') !== -1 || combined.indexOf('描述') !== -1) {
            enField = fallback.el
            break
          }
        }
      }
      if (!enField && englishCandidates.length > 0) enField = englishCandidates[englishCandidates.length - 1].el

      if (zhField) {
        setAreaValue(win, zhField, clean(dom_json.zhDesc))
        payload.zhFound = true
      }
      if (enField) {
        setAreaValue(win, enField, clean(dom_json.enDesc))
        payload.enFound = true
      }

      var buttons = doc.querySelectorAll('button')
      for (i = 0; i < buttons.length; i++) {
        var btnText = clean(buttons[i].textContent || buttons[i].innerText)
        if (btnText !== '保存' || !isVisible(buttons[i])) continue
        buttons[i].click()
        payload.saved = true
        break
      }

      payload.zhDesc = clean(dom_json.zhDesc)
      payload.enDesc = clean(dom_json.enDesc)
      return JSON.stringify(payload)
    }
    catch (e) {
      return JSON.stringify({error: e && e.message ? e.message : 'unknown-error', url: location.href})
    }
    dom finish
    echo save_result=`dom_result`

    wait 10

    dom_json = {productName: current_name}
    dom begin
    try {
      function clean(value) {
        return (value || '').replace(/\s+/g, ' ').replace(/^\s+|\s+$/g, '')
      }
      function isVisible(el) {
        if (!el) return false
        if (el.offsetParent !== null) return true
        if (el.getClientRects && el.getClientRects().length > 0) return true
        return false
      }
      function setInputValue(win, el, value) {
        if (!el) return false
        var descriptor = Object.getOwnPropertyDescriptor(win.HTMLInputElement.prototype, 'value')
        if (descriptor && descriptor.set) descriptor.set.call(el, value)
        else el.value = value
        el.focus()
        el.dispatchEvent(new win.Event('input', {bubbles: true}))
        el.dispatchEvent(new win.Event('change', {bubbles: true}))
        el.dispatchEvent(new win.KeyboardEvent('keydown', {bubbles: true, key: 'Enter', code: 'Enter', keyCode: 13, which: 13}))
        el.dispatchEvent(new win.KeyboardEvent('keyup', {bubbles: true, key: 'Enter', code: 'Enter', keyCode: 13, which: 13}))
        if (typeof el.blur === 'function') el.blur()
        return true
      }

      var payload = {iframeFound: false, rowFound: false, clickedEdit: false, url: location.href}
      var frame = document.querySelector('#merchant_mainContentIframe, iframe')
      if (!frame) return JSON.stringify(payload)
      payload.iframeFound = true
      var win = frame.contentWindow
      var doc = frame.contentDocument || (win && win.document)
      if (!doc || !win) return JSON.stringify(payload)

      var searchInput = doc.querySelector('input[placeholder="搜索商品名称"]')
      if (searchInput) setInputValue(win, searchInput, clean(dom_json.productName))

      var rows = doc.querySelectorAll('tr')
      var i = 0
      for (i = 0; i < rows.length; i++) {
        var text = clean(rows[i].textContent || rows[i].innerText)
        if (!text || text.indexOf(clean(dom_json.productName)) === -1) continue
        payload.rowFound = true
        var editLink = rows[i].querySelector('span.spu-table-action-link')
        if (editLink && clean(editLink.textContent || editLink.innerText) === '编辑' && isVisible(editLink)) {
          editLink.click()
          payload.clickedEdit = true
        }
        break
      }
      return JSON.stringify(payload)
    }
    catch (e) {
      return JSON.stringify({error: e && e.message ? e.message : 'unknown-error', url: location.href})
    }
    dom finish
    echo reopen_result=`dom_result`

    wait 8

    dom_json = {productName: current_name, zhDesc: current_zh_desc, enDesc: current_en_desc}
    dom begin
    try {
      function clean(value) {
        return (value || '').replace(/\s+/g, ' ').replace(/^\s+|\s+$/g, '')
      }
      function isVisible(el) {
        if (!el) return false
        if (el.offsetParent !== null) return true
        if (el.getClientRects && el.getClientRects().length > 0) return true
        return false
      }
      function nearFieldLabel(el) {
        var node = el
        var hop = 0
        while (node && hop < 6) {
          var text = clean(node.textContent || node.innerText)
          if (text && text.length <= 120) return text
          node = node.parentElement
          hop += 1
        }
        return ''
      }

      var payload = {iframeFound: false, zhValue: '', enValue: '', matchedZh: false, matchedEn: false, url: location.href}
      var frame = document.querySelector('#merchant_mainContentIframe, iframe')
      if (!frame) return JSON.stringify(payload)
      payload.iframeFound = true
      var doc = frame.contentDocument || (frame.contentWindow && frame.contentWindow.document)
      if (!doc) return JSON.stringify(payload)

      var textareas = doc.querySelectorAll('textarea')
      var visibleAreas = []
      var i = 0
      for (i = 0; i < textareas.length; i++) {
        if (isVisible(textareas[i])) visibleAreas.push(textareas[i])
      }

      var zhField = doc.querySelector('textarea[placeholder="请描述您的商品"]')
      if (!zhField || !isVisible(zhField)) zhField = null
      var enField = null

      for (i = 0; i < visibleAreas.length; i++) {
        if (zhField && visibleAreas[i] === zhField) continue
        var placeholder = clean(visibleAreas[i].getAttribute('placeholder') || '')
        var label = nearFieldLabel(visibleAreas[i]).toLowerCase()
        if (placeholder.indexOf('商品名称') !== -1 || label.indexOf('商品名称') !== -1) continue
        if (label.indexOf('english') !== -1 || label.indexOf('英文') !== -1) {
          enField = visibleAreas[i]
          break
        }
      }
      if (!enField && visibleAreas.length >= 2) enField = visibleAreas[visibleAreas.length - 1]

      if (zhField) payload.zhValue = clean(zhField.value || '')
      if (enField) payload.enValue = clean(enField.value || '')
      payload.matchedZh = payload.zhValue === clean(dom_json.zhDesc)
      payload.matchedEn = !payload.enValue || payload.enValue === clean(dom_json.enDesc)
      return JSON.stringify(payload)
    }
    catch (e) {
      return JSON.stringify({error: e && e.message ? e.message : 'unknown-error', url: location.href})
    }
    dom finish
    echo verify_result=`dom_result`
