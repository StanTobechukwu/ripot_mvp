const {test} = require('node:test');
const assert = require('node:assert/strict');
const {countryDefinitions} = require('../scripts/paystack-setup');
const {plansForMarket, validateCatalog} = require('../paystack');
const countries = require('../billing-countries.json');
const fixture = [{country:'US', monthlyNgn:'12000', annualNgn:'120000'}, {country:'GB', monthlyNgn:'11000.50', annualNgn:'110005'}];
// Fixture amounts are not approved production prices and are never loaded by setup.
test('country offers keep exact NGN subunits and do not invent an overseas fallback', () => {
  const plans = countryDefinitions(fixture).map((p,i)=>({...p,code:`PLN_fixture${i}`}));
  validateCatalog({mode:'test', plans});
  assert.equal(plansForMarket(plans,'US')[0].amount,1200000);
  assert.equal(plansForMarket(plans,'GB')[0].amount,1100050);
  assert.deepEqual(plansForMarket(plans,'IN'),[]);
  assert.deepEqual(plansForMarket(plans,'NG'),[]);
  assert.deepEqual(plansForMarket(plans,'ZZ'),[]);
});
test('a named country cannot bypass its offer with the generic overseas plan', () => {
  const specific = countryDefinitions(fixture);
  const generic = {id:'generic',amount:600000,currency:'NGN',interval:'monthly',markets:['international'],enabled:true};
  const plans = [...specific,generic];
  assert.deepEqual(plansForMarket(plans,'US').map(p=>p.id),['us_ngn_monthly','us_ngn_annual']);
  assert.deepEqual(plansForMarket(plans,'CA').map(p=>p.id),['generic']);
  assert.deepEqual(plansForMarket(plans,'NG'),[]);
});
test('missing, rounded, duplicate, invalid and Nigeria override prices fail before network access', () => {
  for (const rows of [[], [{country:'US',monthlyNgn:'12'}], [{country:'ZZ',monthlyNgn:'2500',annualNgn:'25000'}],
    [{country:'NG',monthlyNgn:'2500',annualNgn:'25000'}], [fixture[0],fixture[0]],
    [{...fixture[0], monthlyNgn:'12000.001'}], [{...fixture[0], monthlyNgn:12000}],
    [{...fixture[0], annualNgn:'1e6'}], [{...fixture[0], monthlyNgn:'999999999999999999'}]]) {
    assert.throws(()=>countryDefinitions(rows));
  }
  assert.equal(new Set(countries.map(c=>c.code)).size,countries.length);
  assert(countries.some(c=>c.code==='NG' && c.label==='Nigeria'));
});

test('overseas monthly and annual prices must each exceed their Nigerian counterpart', () => {
  for(const change of [{monthlyNgn:'2500'},{monthlyNgn:'2499.99'},{annualNgn:'25000'},{annualNgn:'24999.99'}]){
    assert.throws(()=>countryDefinitions([{...fixture[0],...change}]),/higher than the Nigerian price/);
  }
  const plans=countryDefinitions([{country:'US',monthlyNgn:'2500.01',annualNgn:'25000.01'}]);
  assert.deepEqual(plans.map(p=>p.amount),[250001,2500001]);
});
test('manual catalogues cannot bypass the Nigeria discount, while historical prices remain verifiable', () => {
  const local={id:'ng_monthly',code:'PLN_ng',amount:250000,currency:'NGN',interval:'monthly',markets:['NG'],enabled:true};
  for(const amount of [250000,249999]){
    const overseas={...local,id:'us_monthly',code:'PLN_us',amount,markets:['US']};
    assert.throws(()=>validateCatalog({mode:'live',plans:[local,overseas]}),/higher than the Nigerian price/);
    assert.doesNotThrow(()=>validateCatalog({mode:'live',plans:[local,{...overseas,enabled:false}]}));
  }
  assert.throws(()=>validateCatalog({mode:'live',plans:[{...local,markets:['NG','international']}]}),/higher than the Nigerian price/);
});
