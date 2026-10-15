import {test,expect,type Page} from '@playwright/test';
async function layout(page:Page,name:string){await expect(page.locator('body')).toBeVisible();expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBeTruthy();await page.screenshot({path:`test-results/${test.info().project.name}-${name}.png`,fullPage:true});}
async function noProductPhotos(page:Page){await expect(page.locator('main img')).toHaveCount(0);}
test('customer order, edits, persistence, and counter pickup',async({page})=>{
 const errors:string[]=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto('/menu');await expect(page.getByText('Table 5')).toBeVisible();await layout(page,'menu');
 await page.getByRole('button',{name:'Non-coffee',exact:true}).click();await expect(page.getByRole('button',{name:'Ube Milk sold out'})).toBeDisabled();
 await page.getByRole('button',{name:'Pasta',exact:true}).click();await expect(page.getByText('No items are available in this category yet.')).toBeVisible();
 await page.getByRole('button',{name:'Coffee',exact:true}).click();await page.getByRole('link',{name:'Add Vietnamese Coffee'}).click();
 await page.getByLabel('22oz').check();await page.getByLabel('Less Sweet',{exact:true}).check();await page.getByLabel('Note (optional):').fill('Less ice, please');await page.getByRole('button',{name:'Increase quantity'}).click();await noProductPhotos(page);await layout(page,'customization');await page.getByRole('button',{name:'Add to cart',exact:true}).click();
 await expect(page).toHaveURL(/\/cart$/);await expect(page.getByText('₱300.00').first()).toBeVisible();await noProductPhotos(page);await page.reload();await expect(page.getByText('Note: Less ice, please')).toBeVisible();
 await page.getByRole('link',{name:'Edit',exact:true}).click();await expect(page.getByLabel('22oz')).toBeChecked();await page.getByRole('button',{name:'Decrease quantity'}).click();await page.getByRole('button',{name:'Save changes'}).click();await expect(page).toHaveURL(/\/cart$/);await expect(page.getByText('₱150.00').first()).toBeVisible();await layout(page,'cart');
 await page.getByRole('button',{name:'Place order'}).click();await expect(page.getByText('Queueing number:')).toContainText('001');await expect(page.getByText('Pending Payment',{exact:true})).toBeVisible();await noProductPhotos(page);await layout(page,'confirmation');
 await page.getByRole('link',{name:'View order status'}).click();await expect(page.getByText('Please pay at the counter so we can begin preparing your order.')).toBeVisible();await noProductPhotos(page);await layout(page,'status');await page.reload();await expect(page.getByText('Pending Payment',{exact:true})).toBeVisible();
 await page.goto('/cart');await expect(page.getByText('Your cart is empty')).toBeVisible();expect(errors).toEqual([]);
});
test('remove item and recover from invalid routes',async({page})=>{await page.goto('/product/croissant');await page.getByRole('button',{name:'Add to cart',exact:true}).click();await page.getByRole('button',{name:'Remove Croissant'}).click();await expect(page.getByText('Your cart is empty')).toBeVisible();await page.goto('/product/missing');await expect(page.getByText('Page not found')).toBeVisible();await page.goto('/order/missing');await expect(page.getByText('Order not found')).toBeVisible();});
