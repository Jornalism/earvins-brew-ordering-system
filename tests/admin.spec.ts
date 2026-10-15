import {test,expect,type Page} from '@playwright/test';
async function screenshot(page:Page,name:string){await page.evaluate(()=>document.fonts.ready);for(const image of await page.locator('img').all()){await image.scrollIntoViewIfNeeded();await expect(image).toHaveJSProperty('complete',true);expect(await image.evaluate(el=>(el as HTMLImageElement).naturalWidth)).toBeGreaterThan(0);}await page.evaluate(()=>window.scrollTo(0,0));expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await page.screenshot({path:`test-results/${test.info().project.name}-admin-${name}.png`,fullPage:true});}
test('admin layout is compact, aligned, and isolated from customer styles',async({page})=>{
 await page.goto('/admin/orders');await page.getByRole('button',{name:'Load demo orders'}).click();
 const metrics=await page.evaluate(()=>{
  const shell=document.querySelector('.app-shell')!.getBoundingClientRect();
  const cards=[...document.querySelectorAll('.admin-order-card')].map(el=>el.getBoundingClientRect());
  const header=[...document.querySelectorAll('.admin-order-meta')].map(el=>({table:el.querySelector('h2')!.getBoundingClientRect().right,status:el.querySelector('.status-badge')!.getBoundingClientRect().left}));
  return {width:innerWidth,shellWidth:shell.width,columns:new Set(cards.map(c=>c.left)).size,header};
 });
 if(metrics.width===1440){expect(metrics.shellWidth).toBe(1200);expect(metrics.columns).toBe(3);}
 if(metrics.width===768||metrics.width===1024)expect(metrics.columns).toBe(2);
 if(metrics.width<768)expect(metrics.columns).toBe(1);
 for(const heading of metrics.header)expect(heading.table).toBeLessThanOrEqual(heading.status);
 for(const link of await page.getByRole('navigation',{name:'Admin navigation'}).getByRole('link').all())await expect(link).toBeInViewport();
 await page.getByRole('link',{name:'Earvin’s Brew — menu'}).click();await expect(page.getByRole('navigation',{name:'Menu categories'})).toBeVisible();
 expect(await page.locator('.app-shell').evaluate(el=>el.getBoundingClientRect().width)).toBe(Math.min(metrics.width,880));
});
test('queue transitions, history, filtering and persistence',async({page})=>{
 await page.goto('/admin');await page.getByRole('button',{name:'Load demo orders'}).click();
 await expect(page.locator('.admin-order-card')).toHaveCount(3);await screenshot(page,'queue');
 const first=page.getByRole('article',{name:'Queue 001',exact:true});await first.getByRole('button',{name:'Confirm Payment'}).click();await expect(first).toContainText('Preparing');await first.getByRole('button',{name:'Mark Ready'}).click();await expect(first).toContainText('Ready for Pickup');await first.getByRole('button',{name:'Complete Order'}).click();await expect(first).toHaveCount(0);
 page.once('dialog',d=>d.accept());await page.getByRole('article',{name:'Queue 002',exact:true}).getByRole('button',{name:'Cancel',exact:true}).click();
 await page.getByRole('link',{name:'Order History',exact:true}).click();await expect(page.locator('.admin-order-card')).toHaveCount(4);await expect(page.getByRole('article',{name:'Queue 001',exact:true})).toContainText('Completed');await expect(page.getByRole('article',{name:'Queue 002',exact:true})).toContainText('Cancelled');await screenshot(page,'history');
 await page.getByLabel('Date (Philippine time)').fill('2000-01-01');await expect(page.locator('.admin-order-card')).toHaveCount(0);await page.getByRole('button',{name:'Clear filter'}).click();await page.reload();await expect(page.locator('.admin-order-card')).toHaveCount(4);
});
test('existing products remain editable without creation or permanent deletion',async({page,context})=>{
 test.setTimeout(90000); // Covers image decoding, cross-tab updates, and the full edit/archive/restore flow.
 await page.goto('/admin/products');
 await expect(page.getByRole('heading',{name:'Product Management'})).toBeVisible();
 await expect(page.getByRole('button',{name:/add product/i})).toHaveCount(0);
 await expect(page.getByRole('form',{name:'Add product',exact:true})).toHaveCount(0);
 await expect(page.getByRole('button',{name:/delete/i})).toHaveCount(0);
 await expect(page.getByText('To add a new product, please contact your website administrator.',{exact:true})).toBeVisible();
 const count=await page.locator('.admin-product').count();
 await screenshot(page,'products');
 await page.getByRole('searchbox',{name:'Search products'}).fill('Croissant');
 await expect(page.locator('.admin-product')).toHaveCount(1);
 await page.getByRole('searchbox',{name:'Search products'}).fill('');
 const customer=await context.newPage();await customer.goto('/menu');
 await expect(customer.getByRole('link',{name:'Add Vietnamese Coffee'})).toBeVisible();
 await page.getByRole('switch',{name:'Vietnamese Coffee available',exact:true}).click();
 await expect(customer.getByRole('button',{name:'Vietnamese Coffee sold out'})).toBeDisabled();
 await page.getByRole('switch',{name:'Vietnamese Coffee available',exact:true}).click();
 await expect(customer.getByRole('link',{name:'Add Vietnamese Coffee'})).toBeVisible();
 await page.getByRole('button',{name:'Edit Croissant',exact:true}).click();
 await expect(page.getByRole('form',{name:'Edit product',exact:true})).toBeVisible();
 await page.getByLabel('Product name',{exact:true}).fill('Croissant Updated');
 await page.getByRole('textbox',{name:'Description',exact:true}).fill('Updated description for an existing café product.');
 await page.getByRole('combobox',{name:'Category',exact:true}).selectOption('Non-coffee');
 await page.getByLabel('Price (₱)',{exact:true}).fill('75');
 await page.getByLabel('Upload image (up to 1 MB)').setInputFiles('public/images/products/iced latte.jpg');
 await page.getByRole('button',{name:'Add size',exact:true}).click();
 await page.getByLabel('Size 1',{exact:true}).fill('Single');
 await page.getByLabel('Size 1 price',{exact:true}).fill('75');
 await page.getByLabel('Offer sweetness options: Original, Less Sweet, Sweeter',{exact:true}).check();
 await screenshot(page,'product-editor');
 await page.getByRole('button',{name:'Save product'}).click();
 const updated=page.getByRole('article',{name:'Croissant Updated',exact:true});
 await expect(updated).toContainText('₱75.00');
 await expect(page.locator('.admin-product')).toHaveCount(count);
 await customer.getByRole('button',{name:'Non-coffee',exact:true}).click();
 await expect(customer.getByText('Updated description for an existing café product.',{exact:true})).toBeVisible();
 await expect(customer.getByAltText('Croissant Updated')).toHaveAttribute('src',/^data:image\//);
 await customer.getByRole('link',{name:'Add Croissant Updated'}).click();
 await expect(customer.getByLabel('Single',{exact:false})).toBeVisible();
 await expect(customer.getByLabel('Less Sweet',{exact:true})).toBeVisible();
 await expect(customer.locator('main img')).toHaveCount(0);
 await page.reload();await expect(updated).toBeVisible();
 page.once('dialog',d=>d.accept());await page.getByRole('button',{name:'Archive Croissant Updated',exact:true}).click();
 await expect(page.locator('.admin-product')).toHaveCount(count-1);
 await customer.goto('/menu');await customer.getByRole('button',{name:'Non-coffee',exact:true}).click();
 await expect(customer.getByRole('link',{name:'Add Croissant Updated'})).toHaveCount(0);
 await page.getByLabel('Show archived products').check();
 await page.getByRole('button',{name:'Restore',exact:true}).click();
 await page.getByLabel('Show archived products').uncheck();
 await expect(updated).toBeVisible();await expect(page.locator('.admin-product')).toHaveCount(count);
 await customer.reload();await customer.getByRole('button',{name:'Non-coffee',exact:true}).click();
 await expect(customer.getByRole('link',{name:'Add Croissant Updated'})).toBeVisible();
 await page.goto('/admin/products/new');await expect(page.getByRole('heading',{name:'Page not found'})).toBeVisible();
});
test('table QR download, print isolation, table routing and deactivation',async({page})=>{
 await page.goto('/admin/tables');await expect(page.getByAltText('QR code for Table 5')).toBeVisible();await screenshot(page,'tables');
 await page.getByRole('button',{name:'+ Add Table'}).click();await page.getByLabel('Table number',{exact:true}).fill('6');await page.getByRole('button',{name:'Save table'}).click();const table=page.getByRole('article',{name:'Table 6',exact:true});await expect(table.getByAltText('QR code for Table 6')).toBeVisible();
 const download=page.waitForEvent('download');await table.getByRole('link',{name:'Download QR'}).click();expect((await download).suggestedFilename()).toBe('earvins-table-6.png');
 await page.evaluate(()=>{window.print=()=>{}});await table.getByRole('button',{name:'Print QR'}).click();await page.emulateMedia({media:'print'});await expect(table).toBeVisible();await expect(page.getByRole('article',{name:'Table 5',exact:true})).toBeHidden();await page.emulateMedia({media:'screen'});await page.evaluate(()=>window.dispatchEvent(new Event('afterprint')));
 await table.locator('.table-url a').click();await expect(page.locator('.table-indicator')).toHaveText('Table 6');await page.getByRole('link',{name:'Add Vietnamese Coffee'}).click();await page.getByRole('button',{name:'Add to cart',exact:true}).click();await expect(page).toHaveURL(/\/cart$/);await expect(page.getByText('Table 6',{exact:true})).toBeVisible();await page.reload();await page.getByRole('link',{name:'Edit',exact:true}).click();await page.getByRole('button',{name:'Save changes'}).click();await expect(page).toHaveURL(/\/cart$/);await page.getByRole('button',{name:'Place order'}).click();await expect(page.getByText('Table 6',{exact:true})).toBeVisible();
 await page.goto('/admin/tables');page.once('dialog',d=>d.accept());await page.getByRole('article',{name:'Table 6',exact:true}).getByRole('button',{name:'Deactivate'}).click();await page.goto('/menu?table=6');await expect(page.locator('main [role=alert]')).toContainText('inactive');await expect(page.locator('.add-circle').first()).toBeDisabled();
});
test('admin status changes reach the customer order tab',async({page,context})=>{
 await page.goto('/product/croissant');await page.getByRole('button',{name:'Add to cart',exact:true}).click();await expect(page).toHaveURL(/\/cart$/);await page.getByRole('button',{name:'Place order'}).click();await expect(page.locator('.status-badge')).toHaveText('Pending Payment');
 const admin=await context.newPage();await admin.goto('/admin/orders');await admin.getByRole('button',{name:'Confirm Payment'}).click();await expect(page.locator('.status-badge')).toHaveText('Preparing');
});
