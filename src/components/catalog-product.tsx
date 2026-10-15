'use client';
import {useCatalog} from './catalog-provider';
import {ProductForm} from './product-form';
import {EmptyState} from './ui';
export function CatalogProduct({id}:{id:string}){const {products,ready}=useCatalog();if(!ready)return <p className="loading">Loading product…</p>;const product=products.find(p=>p.id===id&&!p.archived);if(!product)return <EmptyState title="Page not found">This product is no longer available.</EmptyState>;return <ProductForm product={product}/>}
