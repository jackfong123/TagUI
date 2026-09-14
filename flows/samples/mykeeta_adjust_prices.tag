// Reusable MyKeeta product price adjustment flow
// Correct UI order: Edit Price -> find product -> change prices -> Confirm
//
// Single product:
// src/tagui flows/samples/mykeeta_adjust_prices.tag -chrome single '港泰蝦餃皇' 51 31
//
// Batch file (tab-separated: product_name, takeaway_price, pickup_price):
// src/tagui flows/samples/mykeeta_adjust_prices.tag -chrome file data/mykeeta_price_updates.txt

// p1 = single | file
// p2 = product name | batch file path
// p3 = takeaway price (single mode)
// p4 = pickup price (single mode; defaults to takeaway price)


js begin
mode = (p1 || 'single').toLowerCase().trim()
target_arg = (p2 || '').trim()
takeaway_arg = (p3 || '').trim()
pickup_arg = (p4 || '').trim()
targets = []
current_name = ''
current_takeaway = ''
current_pickup = ''

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

format_price = function(value) {
    var price = parseFloat(value)
    if (isNaN(price)) return ''
    return price.toFixed(2)
}

if (mode !== 'file' && mode !== 'single') mode = 'single'

if (mode === 'single') {
    targets = [{
        product_name: normalize_product_name(target_arg),
        takeaway_price: format_price(takeaway_arg),
        pickup_price: format_price(pickup_arg || takeaway_arg)
    }]
}
else {
    var fs = require('fs')
    var lines = fs.read(target_arg).trim().split(/\r?\n/)
    for (var i = 0; i < lines.length; i++) {
        if (!lines[i].trim()) continue
        if (i === 0 && lines[i].toLowerCase().indexOf('product_name') !== -1) continue
        var cols = lines[i].split('\t')
        if (cols.length < 2) cols = lines[i].split('|')
        var takeaway = format_price(cols[1] || '')
        targets.push({
            product_name: normalize_product_name(cols[0] || ''),
            takeaway_price: takeaway,
            pickup_price: format_price(cols[2] || '') || takeaway
        })
    }
}
target_count = targets.length
js finish

echo price_adjust_mode=`mode`
echo price_adjust_target_count=`target_count`

for item_index from 1 to target_count
    js begin
    current_name = targets[item_index - 1].product_name || ''
    current_takeaway = targets[item_index - 1].takeaway_price || ''
    current_pickup = targets[item_index - 1].pickup_price || ''
    js finish

    echo adjusting_price_for=`current_name`
    echo target_takeaway=`current_takeaway`
    echo target_pickup=`current_pickup`

    https://merchant.mykeeta.com/web/product
    wait 20

    // Enter the global price editor first. No product checkbox is selected.
    dom begin
    try {
      function clean(value) { return (value || '').replace(/\s+/g, ' ').replace(/^\s+|\s+$/g, '') }
      function visible(el) { return !!el && ((el.offsetParent !== null) || (el.getClientRects && el.getClientRects().length > 0)) }
      var result = {iframeFound: false, clickedEditPrice: false, editorButtonFound: false}
      var frame = document.querySelector('#merchant_mainContentIframe, iframe')
      if (!frame) return JSON.stringify(result)
      result.iframeFound = true
      var doc = frame.contentDocument || (frame.contentWindow && frame.contentWindow.document)
      if (!doc) return JSON.stringify(result)

      var guide = doc.querySelector('button.guideClose_z7qulO, .guideClose_z7qulO')
      if (guide && visible(guide)) guide.click()

      var buttons = doc.querySelectorAll('button')
      for (var i = 0; i < buttons.length; i++) {
        var text = clean(buttons[i].textContent || buttons[i].innerText)
        var cls = (buttons[i].className || '').toString()
        if (text !== '编辑价格' || cls.indexOf('spu-toolbar-action-button') === -1 || !visible(buttons[i])) continue
        result.editorButtonFound = true
        if (!buttons[i].disabled) {
          buttons[i].scrollIntoView({block: 'center'})
          buttons[i].click()
          result.clickedEditPrice = true
        }
        break
      }
      return JSON.stringify(result)
    }
    catch (e) { return JSON.stringify({error: e && e.message ? e.message : 'unknown-error'}) }
    dom finish
    echo open_price_editor=`dom_result`

    wait 10

    // Locate the named row and update its two price inputs.
    dom_json = {productName: current_name, takeawayPrice: current_takeaway, pickupPrice: current_pickup}
    dom begin
    try {
      function clean(value) { return (value || '').replace(/\s+/g, ' ').replace(/^\s+|\s+$/g, '') }
      function normalized(value) {
        return clean(value).replace(/^[0-9]+[\s._-]*/, '').replace(/周期性可售招牌/g, '').replace(/周期性可售/g, '').replace(/可售招牌/g, '').replace(/招牌/g, '').replace(/\s+/g, ' ').replace(/^\s+|\s+$/g, '')
      }
      function setValue(win, el, value) {
        var setter = Object.getOwnPropertyDescriptor(win.HTMLInputElement.prototype, 'value')
        el.focus()
        if (setter && setter.set) setter.set.call(el, value); else el.value = value
        el.dispatchEvent(new win.Event('input', {bubbles: true}))
        el.dispatchEvent(new win.Event('change', {bubbles: true}))
        el.blur()
      }
      var result = {iframeFound: false, rowFound: false, inputCount: 0, takeawayOld: '', pickupOld: '', takeawayNew: '', pickupNew: '', updated: false}
      var frame = document.querySelector('#merchant_mainContentIframe, iframe')
      if (!frame) return JSON.stringify(result)
      result.iframeFound = true
      var win = frame.contentWindow
      var doc = frame.contentDocument || (win && win.document)
      if (!doc || !win) return JSON.stringify(result)

      var names = doc.querySelectorAll('.product-name-row-text')
      var wanted = normalized(dom_json.productName)
      for (var i = 0; i < names.length; i++) {
        if (normalized(names[i].textContent || names[i].innerText) !== wanted) continue
        var row = names[i].closest('tr') || names[i].parentElement
        var inputs = row.querySelectorAll('input.pdCurrencyInput_nz4Nwt, input[class*="pdCurrencyInput"]')
        result.rowFound = true
        result.inputCount = inputs.length
        if (inputs.length < 2) break
        result.takeawayOld = clean(inputs[0].value)
        result.pickupOld = clean(inputs[1].value)
        setValue(win, inputs[0], dom_json.takeawayPrice)
        setValue(win, inputs[1], dom_json.pickupPrice)
        result.takeawayNew = clean(inputs[0].value)
        result.pickupNew = clean(inputs[1].value)
        result.updated = result.takeawayNew === dom_json.takeawayPrice && result.pickupNew === dom_json.pickupPrice
        break
      }
      return JSON.stringify(result)
    }
    catch (e) { return JSON.stringify({error: e && e.message ? e.message : 'unknown-error'}) }
    dom finish
    echo edit_price_result=`dom_result`

    wait 2

    // Save only through the visible exact-text Confirm button. Never click Submit.
    dom begin
    try {
      function clean(value) { return (value || '').replace(/\s+/g, ' ').replace(/^\s+|\s+$/g, '') }
      function visible(el) { return !!el && ((el.offsetParent !== null) || (el.getClientRects && el.getClientRects().length > 0)) }
      var result = {iframeFound: false, confirmFound: false, confirmed: false, confirmCandidates: [], visibleButtons: []}
      var frame = document.querySelector('#merchant_mainContentIframe, iframe')
      if (!frame) return JSON.stringify(result)
      result.iframeFound = true
      var doc = frame.contentDocument || (frame.contentWindow && frame.contentWindow.document)
      if (!doc) return JSON.stringify(result)
      var buttons = doc.querySelectorAll('button')
      for (var i = 0; i < buttons.length; i++) {
        var buttonText = clean(buttons[i].textContent || buttons[i].innerText)
        if (visible(buttons[i]) && buttonText) result.visibleButtons.push(buttonText)
        if (buttonText !== '确认') continue
        result.confirmCandidates.push({visible: visible(buttons[i]), disabled: !!buttons[i].disabled, cls: (buttons[i].className || '').toString()})
        if (!visible(buttons[i])) continue
        result.confirmFound = true
        if (!buttons[i].disabled) {
          buttons[i].scrollIntoView({block: 'center'})
          buttons[i].click()
          result.confirmed = true
        }
        break
      }
      return JSON.stringify(result)
    }
    catch (e) { return JSON.stringify({error: e && e.message ? e.message : 'unknown-error'}) }
    dom finish
    echo confirm_price_update=`dom_result`

    wait 10

    // Read the row back from the normal product list to verify persistence.
    dom_json = {productName: current_name}
    dom begin
    try {
      function setValue(win, el, value) {
        var setter = Object.getOwnPropertyDescriptor(win.HTMLInputElement.prototype, 'value')
        if (setter && setter.set) setter.set.call(el, value); else el.value = value
        el.dispatchEvent(new win.Event('input', {bubbles: true}))
        el.dispatchEvent(new win.Event('change', {bubbles: true}))
      }
      var result = {searchFound: false, searchApplied: false}
      var frame = document.querySelector('#merchant_mainContentIframe, iframe')
      if (!frame) return JSON.stringify(result)
      var win = frame.contentWindow
      var doc = frame.contentDocument || (win && win.document)
      if (!doc || !win) return JSON.stringify(result)
      var input = doc.querySelector('input[placeholder="搜索商品名称"]')
      if (input) { result.searchFound = true; setValue(win, input, dom_json.productName); result.searchApplied = true }
      return JSON.stringify(result)
    }
    catch (e) { return JSON.stringify({error: e && e.message ? e.message : 'unknown-error'}) }
    dom finish
    wait 5

    dom_json = {productName: current_name, takeawayPrice: current_takeaway, pickupPrice: current_pickup}
    dom begin
    try {
      function clean(value) { return (value || '').replace(/\s+/g, ' ').replace(/^\s+|\s+$/g, '') }
      function price(value) { return clean(value).replace(/[$,]/g, '') }
      function equalPrice(a, b) { return parseFloat(price(a)) === parseFloat(price(b)) }
      var result = {iframeFound: false, rowFound: false, takeawayValue: '', pickupValue: '', matchedTakeaway: false, matchedPickup: false}
      var frame = document.querySelector('#merchant_mainContentIframe, iframe')
      if (!frame) return JSON.stringify(result)
      result.iframeFound = true
      var doc = frame.contentDocument || (frame.contentWindow && frame.contentWindow.document)
      if (!doc) return JSON.stringify(result)
      var names = doc.querySelectorAll('.product-name-row-text')
      for (var i = 0; i < names.length; i++) {
        if (clean(names[i].textContent || names[i].innerText).indexOf(clean(dom_json.productName)) === -1) continue
        var row = names[i].closest('tr') || names[i].parentElement
        result.rowFound = true
        var takeaway = row.querySelector('td.kd-tableNew-cell-num-3 .priceContainer, td.kd-tableNew-cell-num-3')
        var pickup = row.querySelector('td.kd-tableNew-cell-num-5 .priceContainer, td.kd-tableNew-cell-num-5')
        if (takeaway) result.takeawayValue = price(takeaway.textContent || takeaway.innerText)
        if (pickup) result.pickupValue = price(pickup.textContent || pickup.innerText)
        result.matchedTakeaway = equalPrice(result.takeawayValue, dom_json.takeawayPrice)
        result.matchedPickup = equalPrice(result.pickupValue, dom_json.pickupPrice)
        break
      }
      return JSON.stringify(result)
    }
    catch (e) { return JSON.stringify({error: e && e.message ? e.message : 'unknown-error'}) }
    dom finish
    echo verify_price_update=`dom_result`
