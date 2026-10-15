import {test, expect} from '@playwright/test';

test('categories scroll by keyboard and long menu text stays clear of Add', async ({page}) => {
  await page.goto('/menu');
  const nav = page.getByRole('navigation', {name:'Menu categories'});
  await expect(nav).toHaveCSS('scrollbar-width','none');
  await page.getByRole('button',{name:'Coffee',exact:true}).focus();
  for(let i=0;i<6;i++) await page.keyboard.press('Tab');
  const last = page.getByRole('button',{name:'Add-ons',exact:true});
  await expect(last).toBeFocused();
  await expect(last).toBeInViewport();
  await page.keyboard.press('Enter');
  await expect(last).toHaveAttribute('aria-pressed','true');
  await page.getByRole('button',{name:'Coffee',exact:true}).click();
  await page.locator('.product-info').first().evaluate(el => {
    el.querySelector('h2')!.textContent = 'Vietnamese Coffee with a very long product name';
    el.querySelector('p')!.textContent = 'A longer description with SuperLongUnbrokenTextForWrappingValidation to check the available space.';
  });
  const bounds = await page.locator('.product-row').first().evaluate(el => {
    const info = el.querySelector('.product-info')!.getBoundingClientRect();
    const add = el.querySelector('.add-circle')!.getBoundingClientRect();
    return {textRight:info.right,buttonLeft:add.left,overflow:document.documentElement.scrollWidth>innerWidth};
  });
  expect(bounds.textRight).toBeLessThan(bounds.buttonLeft);
  expect(bounds.overflow).toBe(false);
});

test('all five order statuses show counter instructions without product pictures', async ({page}) => {
  const states = [
    ['Pending Payment','Please pay at the counter so we can begin preparing your order.'],
    ['Preparing','We’re preparing your order. Please wait for your queue number to be called.'],
    ['Ready for Pickup','Your order is ready! Please collect it at the counter.'],
    ['Completed','Thank you for visiting Earvin’s Brew. Enjoy your order!'],
    ['Cancelled','This order has been cancelled. Please speak to our counter staff if you need help.'],
  ];
  await page.addInitScript(states => {
    localStorage.setItem('earvins-customer-demo-v1',JSON.stringify({cart:[],orders:states.map(([status],index)=>({id:`status-preview-${index}`,queue:'001',table:5,status,items:[{id:'item',productId:'vietnamese-coffee',name:'Vietnamese Coffee',size:'22oz',sweetness:'Less Sweet',note:'Less ice',quantity:2,price:150}]}))}));
  },states);
  for(const [index,[status,message]] of states.entries()){
    await page.goto(`/order/status-preview-${index}/status`);
    await expect(page.locator('.status-badge')).toHaveText(status);
    await expect(page.getByRole('status')).toHaveText(message);
    await expect(page.getByText('Table 5',{exact:true})).toBeVisible();
    await expect(page.locator('.order-panel > h2').first()).toContainText('001');
    await expect(page.locator('main img')).toHaveCount(0);
    expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
    await page.screenshot({path:`test-results/${test.info().project.name}-status-${status.replaceAll(' ','-')}.png`,fullPage:true});
  }
});
