import { test, expect } from '@playwright/test';

test('selected edge category is fully revealed and empty menu balances footer space', async ({page}) => {
  await page.goto('/menu');
  await page.evaluate(() => document.fonts.ready);
  const nav = page.getByRole('navigation', {name:'Menu categories'});
  const last = page.getByRole('button', {name:'Add-ons',exact:true});
  // Trigger selection without Playwright scrolling the button for us.
  await last.evaluate(el => (el as HTMLButtonElement).click());
  await expect(last).toHaveAttribute('aria-pressed','true');
  const bounds = await last.evaluate(el => {
    const button=el.getBoundingClientRect();
    const nav=el.parentElement!.getBoundingClientRect();
    return {left:button.left,right:button.right,navLeft:nav.left,navRight:nav.right};
  });
  expect(bounds.left).toBeGreaterThanOrEqual(bounds.navLeft);
  expect(bounds.right).toBeLessThanOrEqual(bounds.navRight);
  await expect(nav).toHaveCSS('scrollbar-width','none');
  await expect(page.locator('.category-empty')).toHaveText('No items are available in this category yet.');
  await expect(page.locator('.category-empty h2')).toHaveCount(0);
  const layout = await page.evaluate(() => {
    const footer=document.querySelector('footer')!.getBoundingClientRect();
    const list=document.querySelector('.menu-list')!.getBoundingClientRect();
    const message=document.querySelector('.category-empty')!.getBoundingClientRect();
    return {footerBottom:footer.bottom,viewport:innerHeight,spaceAbove:message.top-list.top,spaceBelow:list.bottom-message.bottom,pageWidth:document.documentElement.scrollWidth,width:innerWidth};
  });
  expect(layout.footerBottom).toBeLessThanOrEqual(layout.viewport);
  expect(layout.viewport-layout.footerBottom).toBeLessThanOrEqual(29);
  expect(Math.abs(layout.spaceAbove-layout.spaceBelow)).toBeLessThan(2);
  expect(layout.pageWidth).toBeLessThanOrEqual(layout.width);
  await page.screenshot({path:`test-results/${test.info().project.name}-empty-menu.png`,fullPage:true});
});

test('menu stays compact with one category row and aligned controls', async ({ page }) => {
  await page.goto('/menu');
  await page.getByRole('heading', { name: 'Vietnamese Coffee' }).waitFor();
  await page.evaluate(() => document.fonts.ready);
  const metrics = await page.evaluate(() => {
    const box = (selector: string) => document.querySelector(selector)!.getBoundingClientRect();
    const logo = box('.brand-logo');
    const shell = box('.app-shell');
    const buttons = [...document.querySelectorAll('.categories button')].map(el => el.getBoundingClientRect());
    const rows = [...document.querySelectorAll('.product-row')].map(el => {
      const row = el.getBoundingClientRect();
      const picture = el.querySelector('img')!.getBoundingClientRect();
      const add = el.querySelector('.add-circle')!.getBoundingClientRect();
      return {height: row.height, pictureCenter: picture.y + picture.height / 2, addCenter: add.y + add.height / 2};
    });
    return {width: innerWidth, pageWidth: document.documentElement.scrollWidth,
      logoRatio: logo.width / logo.height, headerHeight: box('.brand-header').height,
      shellWidth: shell.width, shellCenter: shell.x + shell.width / 2,
      categoryTops: buttons.map(b => b.top), rows};
  });
  expect(metrics.pageWidth).toBeLessThanOrEqual(metrics.width);
  expect(metrics.logoRatio).toBeCloseTo(1012 / 527, 2);
  expect(metrics.headerHeight).toBeLessThan(metrics.width === 375 ? 160 : 230);
  expect(metrics.shellCenter).toBeCloseTo(metrics.width / 2, 0);
  if (metrics.width === 1440) expect(metrics.shellWidth).toBe(880);
  expect(new Set(metrics.categoryTops).size).toBe(1);
  for (const row of metrics.rows) {
    expect(row.height).toBeLessThanOrEqual(115);
    expect(Math.abs(row.pictureCenter - row.addCenter)).toBeLessThan(1);
  }
  await expect(page.getByText('Table 5')).toBeVisible();
  await expect(page.getByRole('link', {name: 'Cart, 0 items'})).toBeVisible();
  await page.screenshot({ path: `test-results/${test.info().project.name}-menu-corrected.png`, fullPage: true });
  await page.getByRole('button', {name: 'Add-ons', exact: true}).click();
  await expect(page.getByRole('button', {name: 'Add-ons', exact: true})).toHaveAttribute('aria-pressed', 'true');
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBeTruthy();
});
