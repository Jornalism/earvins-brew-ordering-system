import type {Metadata} from 'next';
import '@fontsource/poppins/400.css';
import '@fontsource/poppins/600.css';
import '@fontsource/league-spartan/700.css';
import './globals.css';
import {OrderProvider} from '@/components/order-provider';
import {CatalogProvider} from '@/components/catalog-provider';
import {BrandHeader} from '@/components/ui';
export const metadata:Metadata={title:"Earvin’s Brew | Café & Bakery",description:'Order your café favorites for counter pickup at Earvin’s Brew.'};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="en"><body><CatalogProvider><OrderProvider><a className="skip-link" href="#main">Skip to content</a><div className="app-shell"><BrandHeader/><main id="main">{children}</main><footer>Earvin’s Brew · Café & Bakery</footer></div></OrderProvider></CatalogProvider></body></html>}
